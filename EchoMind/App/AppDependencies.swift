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
    let summarizer: any SummarizerService
    /// Held strongly so the store outlives every context/repository derived from it.
    let modelContainer: ModelContainer

    /// Mirrors `settingsStore.onboardingComplete` but observable, so flipping it
    /// on completion re-renders `RootView` without an async flash (§2.7).
    var onboardingComplete: Bool

    init(container: ModelContainer, permissions: any PermissionManaging) {
        self.modelContainer = container
        self.sessionRepository = SwiftDataSessionRepository(modelContainer: container)
        self.documentRepository = SwiftDataDocumentRepository(modelContainer: container)
        self.chunkRepository = SwiftDataChunkRepository(modelContainer: container)
        self.permissions = permissions
        self.audioCapturing = AudioEngineManager()
        self.transcriptionService = SpeechAnalyzerTranscriber()
        self.speechAssets = SpeechAssetManager()
        let budgeter = TokenBudgeter()
        let gateway = FoundationModelService()
        self.tokenBudgeter = budgeter
        self.modelGateway = gateway
        self.availabilityMonitor = ModelAvailabilityMonitor()
        self.summarizer = MapReduceSummarizer(gateway: gateway, budgeter: budgeter)
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
