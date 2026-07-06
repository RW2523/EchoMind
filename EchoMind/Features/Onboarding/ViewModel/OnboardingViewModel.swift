import Foundation

/// Drives the onboarding step machine and persists the flags. `consentAcknowledged`
/// is written when leaving the consent step; `onboardingComplete` only when the
/// final step finishes — so killing the app mid-flow restarts onboarding (§2.7).
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome, privacy, consent, permissionPriming
    }

    private(set) var step: Step = .welcome

    private let settingsStore: AppSettingsStore
    private let onComplete: () -> Void

    init(settingsStore: AppSettingsStore, onComplete: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.onComplete = onComplete
    }

    var isFirstStep: Bool { step == .welcome }

    var primaryButtonTitle: String {
        step == .permissionPriming ? "Get Started" : "Continue"
    }

    func advance() {
        switch step {
        case .welcome:
            step = .privacy
        case .privacy:
            step = .consent
        case .consent:
            settingsStore.setConsentAcknowledged(true)
            step = .permissionPriming
        case .permissionPriming:
            settingsStore.setOnboardingComplete(true)
            onComplete()
        }
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}
