import SwiftUI

/// Switches between onboarding and the main app on the persisted onboarding
/// flag. Reads it synchronously via the observable `AppDependencies` so there's
/// no flash of the wrong screen at launch (§2.7).
struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

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
        // F4: full-screen gate while locked. Lock state is read synchronously at
        // launch — no content flash. (A sheet that was up when the app backgrounded
        // presents above this overlay; acceptable v1 trade-off.)
        .overlay {
            if dependencies.appLock.isLocked {
                AppLockView(controller: dependencies.appLock)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            dependencies.appLock.handleScenePhase(phase)
            if phase == .active, dependencies.appLock.isLocked {
                // One automatic prompt per lock cycle — a cancelled prompt does NOT
                // loop; the lock screen's button is the retry path.
                Task { await dependencies.appLock.autoUnlockIfNeeded() }
            }
        }
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
        case "orb":
            VoiceOrbGallery()
        case "voice":
            VoiceRouteHarness()
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

/// Presents the live voice conversation exactly as the Ask tab does — for
/// reproducing voice-mode issues without hand-tapping (`--screen voice`).
private struct VoiceRouteHarness: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var voice: VoiceSessionController?

    var body: some View {
        Group {
            if let voice {
                VoiceConversationView(voice: voice,
                                      suggestBetterVoice: dependencies.shouldSuggestBetterVoice) { }
            } else {
                BrandBackground()
            }
        }
        .task {
            guard voice == nil else { return }
            let input = LiveVoiceInput(audio: dependencies.audioCapturing,
                                       transcription: dependencies.transcriptionService,
                                       permissions: dependencies.permissions,
                                       assets: dependencies.speechAssets)
            voice = VoiceSessionController(input: input,
                                          synthesizer: dependencies.makeSpeechSynthesizer(),
                                          onQuestion: { _ in "Test answer." },
                                          onQuestionStream: { _ in
                                              AsyncThrowingStream { $0.yield("Test answer."); $0.finish() }
                                          })
        }
    }
}

/// Static gallery of the voice orb in every state — for eyeballing the visual
/// without a mic/device (screenshot route `--screen orb`).
private struct VoiceOrbGallery: View {
    private let modes: [(VoiceOrb.Mode, String)] = [
        (.idle, "Idle"), (.listening, "Listening"), (.thinking, "Thinking"), (.speaking, "Speaking"),
    ]
    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.bg, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 20) {
                ForEach(modes, id: \.1) { mode, name in
                    HStack(spacing: 18) {
                        VoiceOrb(mode: mode, level: mode == .listening ? 0.6 : 0)
                            .frame(width: 110, height: 110)
                        Text(name).font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                }
            }
        }
    }
}
#endif
