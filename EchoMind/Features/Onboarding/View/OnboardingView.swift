import SwiftUI

/// Non-swipeable onboarding pager — forward only via buttons, so the consent
/// step can't be skipped by swiping (§2.7). Restyled with the brand backdrop,
/// progress dots, and a gradient primary action (V2 §D).
struct OnboardingView: View {
    @State var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            BrandBackground(intensity: 0.15)
            VStack(spacing: DS.xl) {
                Group {
                    switch viewModel.step {
                    case .welcome: WelcomeStepView()
                    case .privacy: PrivacyStepView()
                    case .consent: ConsentStepView()
                    case .permissionPriming: PermissionPrimingStepView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24))))

                progressDots

                HStack(spacing: DS.md) {
                    if !viewModel.isFirstStep {
                        Button("Back") { withAnimation(.spring(duration: 0.35)) { viewModel.goBack() } }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    Button(viewModel.primaryButtonTitle) {
                        withAnimation(.spring(duration: 0.35)) { viewModel.advance() }
                    }
                    .buttonStyle(BrandButtonStyle())
                }
                .padding(.horizontal, DS.xl)
                .padding(.bottom, DS.lg)
            }
        }
        .animation(.spring(duration: 0.35), value: viewModel.step)
    }

    private var progressDots: some View {
        HStack(spacing: DS.sm) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == viewModel.step ? DS.brand : Color.secondary.opacity(0.25))
                    .frame(width: step == viewModel.step ? 22 : 7, height: 7)
            }
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView(viewModel: OnboardingViewModel(
        settingsStore: AppDependencies.preview().settingsStore, onComplete: {}))
        .echoMindStyle()
}
#endif
