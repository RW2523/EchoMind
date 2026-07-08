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
    let summarizer: any SummarizerService
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
        // V2: NLEmbedding.sentenceEmbedding works in the simulator AND on device
        // (the NLContextualEmbedding E5 model won't compile in the simulator).
        let embedder = NLEmbeddingService()
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
        let aiSettings = AISettingsStore()
        self.aiSettings = aiSettings
        #if canImport(MLXLLM)
        self.modelDownloader = MLXModelDownloader()
        #else
        self.modelDownloader = UnavailableModelDownloadService()
        #endif
        // Routed gateway (V2 §B4): Apple FM primary, local LLM when downloaded,
        // retrieval-only otherwise. `local` stays nil until the Phase 15 downloader
        // provides an engine; the router then never routes local. Summarizer and RAG
        // consume the same `ModelGateway` seam and are unaware routing exists.
        let routing = RoutingModelGateway(
            apple: FoundationModelService(),
            local: nil,
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
        self.summarizer = MapReduceSummarizer(gateway: routing, budgeter: budgeter)
        self.ragService = RAGPipeline(
            chunks: chunkRepo, embedder: embedder, search: VectorSearch(),
            gateway: routing, budgeter: budgeter,
            availability: { await MainActor.run { monitor.status } })
        let store = AppSettingsStore(container: container)
        self.settingsStore = store
        self.onboardingComplete = store.onboardingComplete
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
