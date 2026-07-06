import Testing
import Foundation
@testable import EchoMind

@Suite struct SessionCascadeDeleteTests {
    @Test func deletingSessionLeavesNoSegmentsOrChunks() async throws {
        let container = try ModelContainerFactory.inMemory()
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let id = UUID()

        try await sessions.create(SessionSnapshot(id: id, title: "Doomed"))
        try await sessions.appendSegment(SegmentSnapshot(sessionId: id, text: "a", startTime: 0, endTime: 1), toSession: id)
        try await sessions.appendSegment(SegmentSnapshot(sessionId: id, text: "b", startTime: 1, endTime: 2), toSession: id)
        try await chunks.insert([
            ChunkSnapshot(sourceId: id, sourceType: .session, text: "c", chunkIndex: 0),
        ])

        try await sessions.delete(id: id)

        let freshSessions = SwiftDataSessionRepository(modelContainer: container)
        let freshChunks = SwiftDataChunkRepository(modelContainer: container)
        #expect(try await freshSessions.fetchAll().isEmpty)
        #expect(try await freshSessions.fetchSegments(sessionId: id).isEmpty)
        #expect(try await freshChunks.fetchAll().isEmpty)
    }

    @Test func deleteChunksBySourceTypeOnlyRemovesMatching() async throws {
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let shared = UUID()
        try await chunks.insert([
            ChunkSnapshot(sourceId: shared, sourceType: .session, text: "s", chunkIndex: 0),
            ChunkSnapshot(sourceId: shared, sourceType: .document, text: "d", chunkIndex: 0),
        ])
        try await chunks.deleteChunks(sourceId: shared, sourceType: .session)
        let remaining = try await SwiftDataChunkRepository(modelContainer: container).fetchAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.sourceType == .document)
    }
}
