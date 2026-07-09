import SwiftUI

/// Switches between onboarding and the main app on the persisted onboarding
/// flag. Reads it synchronously via the observable `AppDependencies` so there's
/// no flash of the wrong screen at launch (§2.7).
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        Group {
            if dependencies.onboardingComplete {
                #if DEBUG
                if let screen = Self.screenArg {
                    ScreenshotRouter(screen: screen)
                } else {
                    MainTabView()
                }
                #else
                MainTabView()
                #endif
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

    #if DEBUG
    /// `--screen report|memory` deep-links a single screen for App Store screenshots.
    static var screenArg: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--screen"),
              i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }
    #endif
}

#if DEBUG
/// Renders one deep screen full-bleed for screenshots (Report / Memory).
private struct ScreenshotRouter: View {
    let screen: String
    @Environment(AppDependencies.self) private var dependencies
    @State private var session: SessionSnapshot?

    var body: some View {
        switch screen {
        case "memory":
            NavigationStack { MemoryView() }
        case "sessions":
            NavigationStack { SessionsView() }
        case "ask":
            NavigationStack { AskView() }
        case "report":
            NavigationStack {
                Group {
                    if let session {
                        SessionDetailView(session: session)
                    } else {
                        BrandBackground().task {
                            let recent = (try? await dependencies.sessionRepository.recentSessions(limit: 8)) ?? []
                            session = recent.first { !$0.continuityNotes.isEmpty } ?? recent.first
                        }
                    }
                }
            }
        default:
            MainTabView()
        }
    }
}
#endif
