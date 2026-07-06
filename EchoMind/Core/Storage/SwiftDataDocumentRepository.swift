import Foundation
import SwiftData

@ModelActor
actor SwiftDataDocumentRepository: DocumentRepository {
    func create(_ snapshot: DocumentSnapshot) async throws {
        let document = Document(id: snapshot.id, title: snapshot.title, fileName: snapshot.fileName,
                                fileType: snapshot.fileType, textContent: snapshot.textContent,
                                pageCount: snapshot.pageCount, pageBreaks: snapshot.pageBreaks,
                                status: snapshot.status, createdAt: snapshot.createdAt)
        modelContext.insert(document)
        try modelContext.save()
    }

    func fetchAll() async throws -> [DocumentSnapshot] {
        let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func fetchDocument(id: UUID) async throws -> DocumentSnapshot? {
        try documentModel(id: id)?.snapshot
    }

    func updateStatus(id: UUID, status: DocumentStatus) async throws {
        guard let document = try documentModel(id: id) else { return }
        document.status = status
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        guard let document = try documentModel(id: id) else { return }
        modelContext.delete(document)
        try sweepChunks(sourceId: id)
        try modelContext.save()
    }

    // MARK: - Helpers

    private func documentModel(id: UUID) throws -> Document? {
        var descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func sweepChunks(sourceId: UUID) throws {
        let descriptor = FetchDescriptor<KnowledgeChunk>(predicate: #Predicate { $0.sourceId == sourceId })
        for chunk in try modelContext.fetch(descriptor) { modelContext.delete(chunk) }
    }
}
