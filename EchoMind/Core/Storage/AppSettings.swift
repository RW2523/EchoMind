import Foundation
import SwiftData

/// Single-row app settings table. Accessed only through `AppSettingsStore`
/// fetch-or-create on `@MainActor` (§2.7) to prevent duplicate rows.
/// `embeddingDimension` is nil until Phase 7's first index run (rag.md §6.2).
@Model
final class AppSettings {
    var onboardingComplete: Bool
    var consentAcknowledged: Bool
    var preferredLocale: String?
    var lastIndexRebuild: Date?
    var embeddingDimension: Int?
    /// P17 (gate G3): keep session audio for playback. ON by default. Additive
    /// property with a default → SwiftData lightweight-migrates existing rows.
    var audioRetentionEnabled: Bool = true

    init(onboardingComplete: Bool = false, consentAcknowledged: Bool = false,
         preferredLocale: String? = nil, lastIndexRebuild: Date? = nil,
         embeddingDimension: Int? = nil, audioRetentionEnabled: Bool = true) {
        self.onboardingComplete = onboardingComplete
        self.consentAcknowledged = consentAcknowledged
        self.preferredLocale = preferredLocale
        self.lastIndexRebuild = lastIndexRebuild
        self.embeddingDimension = embeddingDimension
        self.audioRetentionEnabled = audioRetentionEnabled
    }
}
