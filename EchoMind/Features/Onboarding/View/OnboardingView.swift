import SwiftUI

/// Non-swipeable onboarding pager — forward only via buttons, so the consent
/// step can't be skipped by swiping (§2.7).
struct OnboardingView: View {
    @State var viewModel: OnboardingViewModel

    var body: some View {
        VStack {
            Group {
                switch viewModel.step {
                case .welcome: WelcomeStepView()
                case .privacy: PrivacyStepView()
                case .consent: ConsentStepView()
                case .permissionPriming: PermissionPrimingStepView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            HStack {
                if !viewModel.isFirstStep {
                    Button("Back") { withAnimation { viewModel.goBack() } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(viewModel.primaryButtonTitle) { withAnimation { viewModel.advance() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .animation(.default, value: viewModel.step)
    }
}

#if DEBUG
#Preview {
    OnboardingView(viewModel: OnboardingViewModel(
        settingsStore: AppDependencies.preview().settingsStore, onComplete: {}))
}
#endif
