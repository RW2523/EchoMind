import SwiftUI

/// Five-tab shell. Each tab owns its own `NavigationStack` so per-tab
/// navigation state is independent (needed by Phase 4+). Later phases land their
/// feature into an existing slot.
struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack { HomeView() }
            }
            Tab("Sessions", systemImage: "waveform") {
                NavigationStack { SessionsView() }
            }
            Tab("Knowledge", systemImage: "books.vertical") {
                NavigationStack { KnowledgeView() }
            }
            Tab("Ask", systemImage: "sparkles") {
                NavigationStack { AskView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
    }
}
