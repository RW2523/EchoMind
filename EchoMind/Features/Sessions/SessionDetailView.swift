import SwiftUI

/// Full transcript, rename, export, and delete for a session (§4.2).
struct SessionDetailView: View {
    let session: SessionSnapshot
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: SessionDetailViewModel?

    var body: some View {
        Group {
            if let model {
                SessionDetailContent(model: model)
            } else {
                Color.clear
            }
        }
        .task {
            if model == nil {
                let vm = SessionDetailViewModel(session: session, repository: dependencies.sessionRepository)
                model = vm
                await vm.load()
            }
        }
    }
}

private struct SessionDetailContent: View {
    @Bindable var model: SessionDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var showDelete = false

    var body: some View {
        List {
            SummarySection(session: model.session)
            Section("Transcript") {
                if model.segments.isEmpty {
                    Text("No transcript").foregroundStyle(.secondary)
                } else {
                    ForEach(model.segments) { TranscriptSegmentRow(segment: $0) }
                }
            }
        }
        .navigationTitle(model.session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: model.markdownExport,
                              preview: SharePreview(model.session.title)) {
                        Label("Export as Markdown", systemImage: "doc.text")
                    }
                    ShareLink(item: model.textExport,
                              preview: SharePreview(model.session.title)) {
                        Label("Export as Text", systemImage: "doc.plaintext")
                    }
                    Divider()
                    Button { showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { showDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Session", isPresented: $showRename) {
            TextField("Title", text: $model.draftTitle)
            Button("Save") { Task { await model.commitRename() } }
            Button("Cancel", role: .cancel) { model.draftTitle = model.session.title }
        }
        .confirmationDialog("Delete this session?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await model.delete(); dismiss() }
            }
        } message: {
            Text("The transcript and its knowledge entries will be removed.")
        }
    }
}
