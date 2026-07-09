import SwiftUI

/// Five-tab shell. Each tab owns its own `NavigationStack` so per-tab
/// navigation state is independent (needed by Phase 4+). Later phases land their
/// feature into an existing slot.
struct MainTabView: View {
    @State private var selection = 0

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
        #if DEBUG
        // Apply the --tab screenshot arg AFTER state restoration (which otherwise
        // restores the last-selected tab and overrides an initial @State value).
        .onAppear { if let t = Self.tabArg { selection = t } }
        #endif
    }

    #if DEBUG
    private static var tabArg: Int? {
        guard let i = CommandLine.arguments.firstIndex(of: "--tab"),
              i + 1 < CommandLine.arguments.count else { return nil }
        return Int(CommandLine.arguments[i + 1])
    }
    #endif
}
