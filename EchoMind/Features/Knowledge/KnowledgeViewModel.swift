import Foundation

@MainActor
@Observable
final class KnowledgeViewModel {
    private(set) var sources: [KnowledgeSource] = []
    private(set) var isImporting = false
    var importError: String?

    private let documents: any DocumentRepository
    private let sessions: any SessionRepository
    private let importer: any DocumentImportService
    private let indexer: any IndexerService

    init(documents: any DocumentRepository,
         sessions: any SessionRepository,
         importer: any DocumentImportService,
         indexer: any IndexerService) {
        self.documents = documents
        self.sessions = sessions
        self.importer = importer
        self.indexer = indexer
    }

    func load() async {
        let docs = (try? await documents.fetchAll()) ?? []
        let sess = (try? await sessions.recentSessions(limit: nil)) ?? []
        sources = (docs.map(KnowledgeSource.document) + sess.map(KnowledgeSource.session))
            .sorted { $0.date > $1.date }
    }

    func importFile(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let id = try await importer.importDocument(at: url)
            await load()                          // shows "Not indexed yet"
            try? await indexer.indexDocument(id: id)
            await load()                          // reflects .ready
        } catch let error as ImportError {
            importError = error.errorDescription
        } catch {
            importError = error.localizedDescription
        }
    }

    func delete(_ source: KnowledgeSource) async {
        switch source {
        case .document(let doc): try? await documents.delete(id: doc.id)
        case .session(let session): try? await sessions.delete(id: session.id)
        }
        await load()
    }
}
