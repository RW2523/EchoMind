import Foundation

/// Drives the on-device model manager (V2 §B3). Owns per-model download state and
/// mediates consent; persists the "downloaded" and "selected"/"preference" facts
/// through `AISettingsStore` so the router picks them up on the next call.
@MainActor
@Observable
final class AIModelsViewModel {
    nonisolated enum ModelState: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    let models = LocalModelCatalog.all
    var chatModels: [LocalModel] { models.filter { $0.kind == .chat } }
    var embeddingModels: [LocalModel] { models.filter { $0.kind == .embedding } }
    var voiceModels: [LocalModel] { models.filter { $0.kind == .tts } }
    private let downloader: any ModelDownloadService
    private let settings: AISettingsStore

    private(set) var states: [String: ModelState] = [:]
    var showConsent = false
    private var pendingDownload: LocalModel?

    init(downloader: any ModelDownloadService, settings: AISettingsStore) {
        self.downloader = downloader
        self.settings = settings
    }

    var engineLinked: Bool { downloader.engineLinked }
    var selectedModelID: String { settings.selectedModelID }
    var preference: AIPreference {
        get { settings.preference }
        set { settings.preference = newValue }
    }

    func state(for model: LocalModel) -> ModelState { states[model.id] ?? .notDownloaded }

    func load() async {
        for model in models {
            states[model.id] = await downloader.isAvailable(model) ? .ready : (states[model.id] ?? .notDownloaded)
        }
    }

    func select(_ model: LocalModel) { settings.selectedModelID = model.id }

    // MARK: - Embedding model (M2)

    /// Currently selected search embedder id, or nil = built-in NLEmbedding.
    var selectedEmbeddingModelID: String? { settings.selectedEmbeddingModelID }

    func useForSearch(_ model: LocalModel) {
        settings.selectedEmbeddingModelID = model.id
    }

    func useBuiltInEmbedder() {
        settings.selectedEmbeddingModelID = nil
    }

    // MARK: - Voice model (V4)

    var selectedVoiceModelID: String? { settings.selectedVoiceModelID }
    func useForVoice(_ model: LocalModel) { settings.selectedVoiceModelID = model.id }
    func useBuiltInVoice() { settings.selectedVoiceModelID = nil }

    /// Entry point from the UI — routes through consent the first time.
    func requestDownload(_ model: LocalModel) {
        if settings.downloadConsentGiven {
            Task { await download(model) }
        } else {
            pendingDownload = model
            showConsent = true
        }
    }

    func confirmConsent() {
        settings.downloadConsentGiven = true
        showConsent = false
        if let model = pendingDownload {
            pendingDownload = nil
            Task { await download(model) }
        }
    }

    func cancelConsent() {
        showConsent = false
        pendingDownload = nil
    }

    func delete(_ model: LocalModel) async {
        try? await downloader.delete(model)
        settings.markRemoved(model.id)
        states[model.id] = .notDownloaded
    }

    private func download(_ model: LocalModel) async {
        states[model.id] = .downloading(0)
        do {
            try await downloader.download(model) { progress in
                Task { @MainActor in
                    if case .downloading = self.states[model.id] {
                        self.states[model.id] = .downloading(progress)
                    }
                }
            }
            states[model.id] = .ready
            settings.markDownloaded(model.id)
            // First downloaded model becomes the selection if none is usable yet.
            if settings.localModelID == nil { settings.selectedModelID = model.id }
        } catch {
            states[model.id] = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let e = error as? ModelDownloadError {
            switch e {
            case .engineNotLinked: return "Add the MLX package in Xcode first (see PACKAGES.md)."
            case .cancelled: return "Download cancelled."
            case .failed(let m): return m
            }
        }
        return String(describing: error)
    }
}
