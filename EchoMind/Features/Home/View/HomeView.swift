import SwiftUI

/// Home tab placeholder. Becomes the real dashboard (Start Live Transcript, Ask,
/// Import, recent sessions) in Phase 4.
struct HomeView: View {
    var body: some View {
        List {
            Section {
                Text("Start Live Transcript")
                Text("Ask My Knowledge")
                Text("Import Document")
            } header: {
                Text("Coming soon")
            }
        }
        .navigationTitle("EchoMind")
    }
}

#if DEBUG
#Preview { NavigationStack { HomeView() } }
#endif
