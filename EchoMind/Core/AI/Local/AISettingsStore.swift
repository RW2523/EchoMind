import Foundation

/// Lightweight, migration-free store for AI routing preferences (V2 §B4). Backed
/// by `UserDefaults` rather than the SwiftData schema — these are device-local
/// preferences, not user content, so they don't belong in the exportable store and
/// don't warrant a schema migration. Observable so Settings reflects changes live.
@MainActor
@Observable
final class AISettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let preference = "ai.preference"
        static let selectedModel = "ai.selectedModelID"
        static let downloaded = "ai.downloadedModelIDs"
        static let downloadConsent = "ai.modelDownloadConsent"
    }

    private var _preference: AIPreference
    private var _selectedModelID: String
    private var _downloaded: Set<String>
    private var _downloadConsent: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _preference = defaults.string(forKey: Key.preference)
            .flatMap(AIPreference.init(rawValue:)) ?? .auto
        _selectedModelID = defaults.string(forKey: Key.selectedModel) ?? LocalModelCatalog.default.id
        _downloaded = Set(defaults.stringArray(forKey: Key.downloaded) ?? [])
        _downloadConsent = defaults.bool(forKey: Key.downloadConsent)
    }

    /// Whether the user has accepted the one-time "weights download uses the
    /// network" consent. Nothing downloads before this is true.
    var downloadConsentGiven: Bool {
        get { _downloadConsent }
        set { _downloadConsent = newValue; defaults.set(newValue, forKey: Key.downloadConsent) }
    }

    var preference: AIPreference {
        get { _preference }
        set { _preference = newValue; defaults.set(newValue.rawValue, forKey: Key.preference) }
    }

    var selectedModelID: String {
        get { _selectedModelID }
        set { _selectedModelID = newValue; defaults.set(newValue, forKey: Key.selectedModel) }
    }

    var downloadedModelIDs: Set<String> { _downloaded }

    /// The model that can actually serve local inference right now: the selected
    /// one, but only if its weights are downloaded. Nil otherwise → router won't
    /// route local.
    var localModelID: String? {
        _downloaded.contains(_selectedModelID) ? _selectedModelID : nil
    }

    func isDownloaded(_ id: String) -> Bool { _downloaded.contains(id) }

    func markDownloaded(_ id: String) {
        _downloaded.insert(id)
        persistDownloaded()
    }

    func markRemoved(_ id: String) {
        _downloaded.remove(id)
        persistDownloaded()
    }

    private func persistDownloaded() {
        defaults.set(Array(_downloaded), forKey: Key.downloaded)
    }
}
