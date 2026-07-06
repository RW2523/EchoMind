import Foundation
import SwiftData

@ModelActor
actor SwiftDataChunkRepository: ChunkRepository {
    func insert(_ chunks: [ChunkSnapshot]) async throws {
        for snapshot in chunks {
            let chunk = KnowledgeChunk(id: snapshot.id, sourceId: snapshot.sourceId,
                                       sourceType: snapshot.sourceType, text: snapshot.text,
                                       embedding: snapshot.embedding, chunkIndex: snapshot.chunkIndex,
                                       pageNumber: snapshot.pageNumber, timestamp: snapshot.timestamp,
                                       createdAt: snapshot.createdAt)
            modelContext.insert(chunk)
        }
        try modelContext.save()
    }

    func fetchAll() async throws -> [ChunkSnapshot] {
        let descriptor = FetchDescriptor<KnowledgeChunk>(sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func deleteChunks(sourceId: UUID) async throws {
        let descriptor = FetchDescriptor<KnowledgeChunk>(predicate: #Predicate { $0.sourceId == sourceId })
        for chunk in try modelContext.fetch(descriptor) { modelContext.delete(chunk) }
        try modelContext.save()
    }

    func deleteAll() async throws {
        try modelContext.delete(model: KnowledgeChunk.self)
        try modelContext.save()
    }
}
