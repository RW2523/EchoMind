import Foundation
import SwiftData

/// Composition root — the only allowed singleton-ish object (CLAUDE.md). Built
/// once in `EchoMindApp.init`, injected via the SwiftUI environment. Every later
/// service (AudioEngineManager, TranscriptionService, ModelGateway, …) is added
/// here in its phase. View models receive the specific protocols they need.
@MainActor
@Observable
final class AppDependencies {
    let sessionRepository: any SessionRepository
    let documentRepository: any DocumentRepository
    let chunkRepository: any ChunkRepository
    let permissions: any PermissionManaging
    let settingsStore: AppSettingsStore
    let audioCapturing: any AudioCapturing
    let transcriptionService: any TranscriptionService
    let speechAssets: any SpeechAssetManaging
    let tokenBudgeter: TokenBudgeter
    let modelGateway: any ModelGateway
    let availabilityMonitor: any AvailabilityProviding
    let aiSettings: AISettingsStore
    let modelDownloader: any ModelDownloadService
    /// Identity of the embedder resolved this launch (M2) — recorded after a rebuild.
    let embedderIdentity: String
    /// True when the active index was built by a different embedder than the one
    /// resolved this launch (e.g. user switched to EmbeddingGemma) → rebuild needed.
    var embeddingIndexStale: Bool
    let summarizer: any SummarizerService
    let reportGenerator: any ReportGenerating
    let documentImporter: any DocumentImportService
    let embeddingService: any EmbeddingService
    let vectorSearch: VectorSearch
    let indexer: any IndexerService
    let chatRepository: any ChatRepository
    let ragService: any RAGService
    let storageUsageService: any StorageUsageService
    let dataExportService: any DataExportService
    let dataWipeService: any DataWipeService
    /// Held strongly so the store outlives every context/repository derived from it.
    let modelContainer: ModelContainer
    /// Shared on-disk audio store (P17) — same directory used by capture + playback.
    let audioStore = AudioStore()
    /// Speaker diarization (M3) — real only when the FluidAudio package is linked.
    let diarizer: any DiarizationService = {
        #if canImport(FluidAudio)
        return FluidAudioDiarizer()
        #else
        return UnavailableDiarizationService()
        #endif
    }()
    /// Vector store seam (M4). InMemory (brute-force, the shipping default) unless
    /// the sqlite-vec package is linked, in which case on-disk indexing is used.
    let vectorStore: any VectorStore = {
        #if canImport(SQLiteVec)
        if let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask, appropriateFor: nil, create: true) {
            return SQLiteVecVectorStore(url: base.appendingPathComponent("vectors.sqlite"))
        }
        #endif
        return InMemoryVectorStore()
    }()

    /// Mirrors `settingsStore.onboardingComplete` but observable, so flipping it
    /// on completion re-renders `RootView` without an async flash (§2.7).
    var onboardingComplete: Bool

    init(container: ModelContainer, permissions: any PermissionManaging) {
        self.modelContainer = container
        let sessionRepo = SwiftDataSessionRepository(modelContainer: container)
        self.sessionRepository = sessionRepo
        let docRepository = SwiftDataDocumentRepository(modelContainer: container)
        self.documentRepository = docRepository
        let chunkRepo = SwiftDataChunkRepository(modelContainer: container)
        self.chunkRepository = chunkRepo
        self.documentImporter = DefaultDocumentImportService(documents: docRepository)
        let aiSettings = AISettingsStore()
        self.aiSettings = aiSettings
        // M2: resolve the embedder — built-in NLEmbedding by default (0 MB, works
        // in the simulator), upgraded to a downloaded EmbeddingGemma when selected.
        // NLEmbedding is the floor so RAG is never dead.
        let embedderChoice = EmbedderResolver().choice(
            selectedEmbeddingModelID: aiSettings.selectedEmbeddingModelID,
            isDownloaded: { aiSettings.isDownloaded($0) },
            packageLinked: Self.embeddersPackageLinked)
        self.embedderIdentity = embedderChoice.identity
        self.embeddingIndexStale = EmbedderResolver().needsRebuild(
            choice: embedderChoice, activeIdentity: aiSettings.activeEmbedderIdentity)
        // First launch adopts the current embedder as the index's identity.
        if aiSettings.activeEmbedderIdentity == nil {
            aiSettings.activeEmbedderIdentity = embedderChoice.identity
        }
        let embedder = Self.makeEmbedder(choice: embedderChoice)
        self.embeddingService = embedder
        self.vectorSearch = VectorSearch()
        self.indexer = RAGIndexer(documents: docRepository, sessions: sessionRepo,
                                  chunks: chunkRepo, embedder: embedder)
        let chatRepo = SwiftDataChatRepository(modelContainer: container)
        self.chatRepository = chatRepo
        self.storageUsageService = DefaultStorageUsageService(sessions: sessionRepo, documents: docRepository, chunks: chunkRepo)
        self.dataExportService = DefaultDataExportService(sessions: sessionRepo, documents: docRepository)
        self.dataWipeService = DefaultDataWipeService(sessions: sessionRepo, documents: docRepository, chunks: chunkRepo, chat: chatRepo)
        self.permissions = permissions
        self.audioCapturing = AudioEngineManager()
        self.transcriptionService = SpeechAnalyzerTranscriber()
        self.speechAssets = SpeechAssetManager()
        let budgeter = TokenBudgeter()
        self.tokenBudgeter = budgeter
        let monitor = ModelAvailabilityMonitor()
        self.availabilityMonitor = monitor
        #if canImport(MLXLLM)
        self.modelDownloader = MLXModelDownloader()
        #else
        self.modelDownloader = UnavailableModelDownloadService()
        #endif
        // Routed gateway (V2 §B4): Apple FM primary, local LLM when downloaded,
        // retrieval-only otherwise. The local gateway exists only when the MLX
        // package is linked; even then the router won't route to it until the
        // selected model's weights are downloaded (`aiSettings.localModelID`).
        // Summarizer and RAG consume the same `ModelGateway` seam, unaware of routing.
        var localGateway: (any ModelGateway)?
        #if canImport(MLXLLM)
        let selectedModel = LocalModelCatalog.model(id: aiSettings.selectedModelID) ?? LocalModelCatalog.default
        localGateway = LocalLLMGateway(engine: MLXEngine(model: selectedModel))
        #else
        localGateway = nil
        #endif
        let routing = RoutingModelGateway(
            apple: FoundationModelService(),
            local: localGateway,
            router: FeatureRouter(),
            context: {
                await MainActor.run {
                    RoutingModelGateway.Context(
                        availability: monitor.status,
                        localModelID: aiSettings.localModelID,
                        preference: aiSettings.preference,
                        thermal: ThermalLevel(processInfo: ProcessInfo.processInfo.thermalState))
                }
            })
        self.modelGateway = routing
        let summarizer = MapReduceSummarizer(gateway: routing, budgeter: budgeter)
        self.summarizer = summarizer
        self.reportGenerator = ReportPipeline(
            sessions: sessionRepo, summarizer: summarizer,
            availability: { await MainActor.run { monitor.status } })
        self.ragService = RAGPipeline(
            chunks: chunkRepo, embedder: embedder, search: VectorSearch(),
            gateway: routing, budgeter: budgeter,
            availability: { await MainActor.run { monitor.status } })
        let store = AppSettingsStore(container: container)
        self.settingsStore = store
        self.onboardingComplete = store.onboardingComplete
    }

    /// Call after a successful index rebuild: records the current embedder as the
    /// one that built the index and clears the stale flag.
    func markIndexRebuilt() {
        aiSettings.activeEmbedderIdentity = embedderIdentity
        embeddingIndexStale = false
    }

    /// Resolve the TTS voice for the voice agent (V4): downloaded Kokoro if linked +
    /// selected, else the built-in AVSpeech voice.
    func makeSpeechSynthesizer() -> any SpeechSynthesizing {
        let choice = SpeechSynthesizerResolver().choice(
            selectedVoiceModelID: aiSettings.selectedVoiceModelID,
            isDownloaded: { aiSettings.isDownloaded($0) },
            packageLinked: Self.ttsPackageLinked)
        switch choice {
        case .systemAV:
            return SystemSpeechSynthesizer()
        case .kokoro(let id):
            #if canImport(FluidAudioTTS)
            if let model = LocalModelCatalog.model(id: id) { return KokoroSynthesizer(model: model) }
            #endif
            return SystemSpeechSynthesizer()
        }
    }

    private static var ttsPackageLinked: Bool {
        #if canImport(FluidAudioTTS)
        return true
        #else
        return false
        #endif
    }

    private static var embeddersPackageLinked: Bool {
        #if canImport(MLXEmbedders)
        return true
        #else
        return false
        #endif
    }

    private static func makeEmbedder(choice: EmbedderChoice) -> any EmbeddingService {
        switch choice {
        case .builtInNL:
            return NLEmbeddingService()
        case .gemma(let id):
            #if canImport(MLXEmbedders)
            if let model = LocalModelCatalog.model(id: id) {
                return GemmaEmbeddingService(model: model)
            }
            #endif
            return NLEmbeddingService()
        }
    }

    static func live() throws -> AppDependencies {
        let container = try ModelContainerFactory.live()
        return AppDependencies(container: container, permissions: PermissionManager())
    }

    #if DEBUG
    /// In-memory container + stub permissions for SwiftUI previews.
    static func preview() -> AppDependencies {
        do {
            let container = try ModelContainerFactory.inMemory()
            return AppDependencies(container: container, permissions: StubPermissionManager())
        } catch {
            // Previews only; surface loudly rather than silently render empty.
            fatalError("preview container failed: \(error)")
        }
    }
    #endif
}
