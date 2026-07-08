import SwiftUI

/// Switches between onboarding and the main app on the persisted onboarding
/// flag. Reads it synchronously via the observable `AppDependencies` so there's
/// no flash of the wrong screen at launch (§2.7).
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if dependencies.onboardingComplete {
                MainTabView()
            } else {
                OnboardingView(
                    viewModel: OnboardingViewModel(settingsStore: dependencies.settingsStore) {
                        dependencies.onboardingComplete = true
                    }
                )
            }
        }
        .echoMindStyle()
        .task {
            #if DEBUG
            if CommandLine.arguments.contains("--skip-onboarding") { dependencies.onboardingComplete = true }
            #endif
        }
    }
}
