import SwiftUI

/// Five-tab shell. Each tab owns its own `NavigationStack` so per-tab
/// navigation state is independent (needed by Phase 4+). Later phases land their
/// feature into an existing slot.
struct MainTabView: View {
    @State private var selection = MainTabView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack { HomeView() }
            }
            Tab("Sessions", systemImage: "waveform", value: 1) {
                NavigationStack { SessionsView() }
            }
            Tab("Knowledge", systemImage: "books.vertical", value: 2) {
                NavigationStack { KnowledgeView() }
            }
            Tab("Ask", systemImage: "sparkles", value: 3) {
                NavigationStack { AskView() }
            }
            Tab("Settings", systemImage: "gearshape", value: 4) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private static var initialTab: Int {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--tab"),
           i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]) { return n }
        #endif
        return 0
    }
}
