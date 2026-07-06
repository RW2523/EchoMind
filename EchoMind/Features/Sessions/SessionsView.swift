import SwiftUI

/// Date-sorted, searchable session list with swipe-delete (§4.2).
struct SessionsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: SessionsViewModel?
    @State private var searchText = ""

    var body: some View {
        Group {
            if let model {
                List {
                    ForEach(model.sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session, repository: dependencies.sessionRepository)
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { model.sessions[$0].id }
                        Task { await model.delete(ids: ids) }
                    }
                }
                .overlay {
                    if model.sessions.isEmpty {
                        ContentUnavailableView("No Sessions Yet", systemImage: "waveform",
                                               description: Text("Recorded sessions appear here."))
                    }
                }
                .searchable(text: $searchText, prompt: "Search transcripts")
                .task(id: searchText) {
                    try? await Task.sleep(for: .milliseconds(300))
                    await model.applySearch(searchText)
                }
                .refreshable { await model.load() }
            } else {
                Color.clear
            }
        }
        .navigationTitle("Sessions")
        .task {
            if model == nil {
                let vm = SessionsViewModel(repository: dependencies.sessionRepository)
                model = vm
                await vm.load()
            }
        }
    }
}
