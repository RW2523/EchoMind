import SwiftUI

/// Home dashboard: primary actions + the 3 most recent sessions (§4.2).
struct HomeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: HomeViewModel?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LiveTranscriptView()
                } label: {
                    Label("Start Live Transcript", systemImage: "mic.circle.fill")
                }
                NavigationLink {
                    AskView()
                } label: {
                    Label("Ask My Knowledge", systemImage: "sparkles")
                }
                NavigationLink {
                    KnowledgeView()
                } label: {
                    Label("Import Document", systemImage: "doc.badge.plus")
                }
            }

            if let model, !model.recent.isEmpty {
                Section("Recent") {
                    ForEach(model.recent) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session, repository: dependencies.sessionRepository)
                        }
                    }
                }
            }
        }
        .navigationTitle("EchoMind")
        .task {
            if model == nil {
                let vm = HomeViewModel(repository: dependencies.sessionRepository)
                model = vm
                await vm.load()
            } else {
                await model?.load()
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView() }
        .environment(AppDependencies.preview())
}
#endif
