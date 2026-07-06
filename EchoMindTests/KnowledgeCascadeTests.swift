import Testing
import Foundation
@testable import EchoMind

@Suite struct KnowledgeCascadeTests {
    @Test func deletingDocumentRemovesItsChunks() async throws {
        let container = try ModelContainerFactory.inMemory()
        let documents = SwiftDataDocumentRepository(modelContainer: container)
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let id = UUID()

        try await documents.create(DocumentSnapshot(id: id, title: "Doc", fileName: "d.pdf",
                                                    fileType: .pdf, textContent: "hello",
                                                    pageBreaks: [0]))
        try await chunks.insert([
            ChunkSnapshot(sourceId: id, sourceType: .document, text: "c0", chunkIndex: 0),
            ChunkSnapshot(sourceId: id, sourceType: .document, text: "c1", chunkIndex: 1),
        ])

        try await documents.delete(id: id)

        let fresh = SwiftDataChunkRepository(modelContainer: container)
        #expect(try await fresh.fetchAll().isEmpty)
    }
}
