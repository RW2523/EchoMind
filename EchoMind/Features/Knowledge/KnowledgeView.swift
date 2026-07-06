import SwiftUI
import UniformTypeIdentifiers

/// Unified knowledge sources + document import (§4.3).
struct KnowledgeView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: KnowledgeViewModel?
    @State private var showImporter = false

    private static let importTypes: [UTType] = [.pdf, .plainText, UTType(filenameExtension: "md")].compactMap { $0 }

    @ViewBuilder private func destination(for source: KnowledgeSource) -> some View {
        switch source {
        case .document(let doc): DocumentDetailView(documentId: doc.id, initialPageNumber: nil)
        case .session(let session): SessionDetailView(session: session)
        }
    }

    var body: some View {
        Group {
            if let model {
                List {
                    if model.isImporting {
                        HStack { ProgressView(); Text("Importing…").foregroundStyle(.secondary) }
                    }
                    ForEach(model.sources) { source in
                        NavigationLink {
                            destination(for: source)
                        } label: {
                            KnowledgeSourceRow(source: source)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.delete(source) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .overlay {
                    if model.sources.isEmpty && !model.isImporting {
                        ContentUnavailableView("No Knowledge Yet", systemImage: "books.vertical",
                                               description: Text("Import a document or record a session."))
                    }
                }
            } else {
                Color.clear
            }
        }
        .navigationTitle("Knowledge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImporter = true } label: { Label("Import", systemImage: "plus") }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.importTypes,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await model?.importFile(url) }
        }
        .alert("Import Failed", isPresented: Binding(
            get: { model?.importError != nil },
            set: { if !$0 { model?.importError = nil } })) {
            Button("OK", role: .cancel) { model?.importError = nil }
        } message: {
            Text(model?.importError ?? "")
        }
        .task {
            if model == nil {
                let vm = KnowledgeViewModel(documents: dependencies.documentRepository,
                                            sessions: dependencies.sessionRepository,
                                            importer: dependencies.documentImporter,
                                            indexer: dependencies.indexer)
                model = vm
                await vm.load()
            } else {
                await model?.load()
            }
        }
    }
}
