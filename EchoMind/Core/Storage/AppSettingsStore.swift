import Foundation
import SwiftData

/// Fetch-or-create accessor for the single-row `AppSettings` table (§2.7).
/// `@MainActor` so `RootView` can read the onboarding flag synchronously at
/// launch with no async flash-of-wrong-screen. Keeps the `AppSettings` @Model
/// private — callers see only scalar values, honoring the storage boundary.
@MainActor
final class AppSettingsStore {
    /// Held strongly: `ModelContext` alone does not keep its `ModelContainer`
    /// alive, so retaining only the context lets the backing store deallocate
    /// out from under us (use-after-free in CoreData teardown). Own the container.
    private let container: ModelContainer
    private var modelContext: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    var onboardingComplete: Bool { settings().onboardingComplete }
    var consentAcknowledged: Bool { settings().consentAcknowledged }
    var preferredLocale: String? { settings().preferredLocale }
    var embeddingDimension: Int? { settings().embeddingDimension }
    var lastIndexRebuild: Date? { settings().lastIndexRebuild }
    var audioRetentionEnabled: Bool { settings().audioRetentionEnabled }

    func setOnboardingComplete(_ value: Bool) { mutate { $0.onboardingComplete = value } }
    func setConsentAcknowledged(_ value: Bool) { mutate { $0.consentAcknowledged = value } }
    func setPreferredLocale(_ value: String?) { mutate { $0.preferredLocale = value } }
    func setEmbeddingDimension(_ value: Int?) { mutate { $0.embeddingDimension = value } }
    func setLastIndexRebuild(_ value: Date?) { mutate { $0.lastIndexRebuild = value } }
    func setAudioRetentionEnabled(_ value: Bool) { mutate { $0.audioRetentionEnabled = value } }

    // MARK: - Single-row fetch-or-create

    @discardableResult
    private func settings() -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? modelContext.fetch(descriptor).first { return existing }
        let created = AppSettings()
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    private func mutate(_ change: (AppSettings) -> Void) {
        let current = settings()
        change(current)
        try? modelContext.save()
    }
}
