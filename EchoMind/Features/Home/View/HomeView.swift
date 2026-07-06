import SwiftUI

/// Home tab. Live transcription is reachable here from Phase 3; the full
/// dashboard (Ask, Import, recent sessions) fills in during Phase 4.
struct HomeView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    LiveTranscriptView()
                } label: {
                    Label("Start Live Transcript", systemImage: "mic.circle.fill")
                }
            }
            Section("Coming soon") {
                Label("Ask My Knowledge", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
                Label("Import Document", systemImage: "doc.badge.plus")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("EchoMind")
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView() }
        .environment(AppDependencies.preview())
}
#endif
