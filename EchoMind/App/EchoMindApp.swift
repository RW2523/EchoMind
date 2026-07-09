import SwiftUI

@main
struct EchoMindApp: App {
    @State private var dependencies: AppDependencies?
    @State private var launchError: String?

    init() {
        do {
            _dependencies = State(initialValue: try AppDependencies.live())
            _launchError = State(initialValue: nil)
        } catch {
            _dependencies = State(initialValue: nil)
            _launchError = State(initialValue: error.localizedDescription)
        }
    }

    private static var isDemoOrScreenshotLaunch: Bool {
        let args = CommandLine.arguments
        return args.contains("--demo-seed") || args.contains("--screen")
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootView()
                    .environment(dependencies)
                    // R1 hardening: recover reports stranded by an interrupted or
                    // AI-unavailable earlier launch. Skipped for the demo/screenshot
                    // flows so their seeded state stays deterministic.
                    .task {
                        guard !Self.isDemoOrScreenshotLaunch else { return }
                        await dependencies.reportReconciler.reconcile()
                    }
                    #if DEBUG
                    .task { await AskSelfTest.runIfRequested(dependencies) }
                    .task { await DemoSeed.runIfRequested(dependencies) }
                    #endif
            } else {
                StorageUnavailableView(message: launchError ?? "Unknown error")
            }
        }
    }
}
