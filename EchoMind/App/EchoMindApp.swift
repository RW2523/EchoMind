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

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootView()
                    .environment(dependencies)
                    #if DEBUG
                    .task { await AskSelfTest.runIfRequested(dependencies) }
                    #endif
            } else {
                StorageUnavailableView(message: launchError ?? "Unknown error")
            }
        }
    }
}
