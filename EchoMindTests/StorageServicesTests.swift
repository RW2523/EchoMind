import Testing
import Foundation
@testable import EchoMind

@Suite struct StorageServicesTests {
    private func makeStack() throws -> (SwiftDataSessionRepository, SwiftDataDocumentRepository,
                                        SwiftDataChunkRepository, SwiftDataChatRepository) {
        let container = try ModelContainerFactory.inMemory()
        return (SwiftDataSessionRepository(modelContainer: container),
                SwiftDataDocumentRepository(modelContainer: container),
                SwiftDataChunkRepository(modelContainer: container),
                SwiftDataChatRepository(modelContainer: container))
    }

    /// Isolated, empty audio store so tests never see leftover recordings.
    private func tempAudioStore() -> AudioStore {
        AudioStore(baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("echomind-audio-test-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func usageCountsRealBytes() async throws {
        let (sessions, documents, chunks, _) = try makeStack()
        let sessionId = UUID()
        try await sessions.create(SessionSnapshot(id: sessionId, title: "S"))
        try await sessions.appendSegment(SegmentSnapshot(sessionId: sessionId, text: "hello world",
                                                        startTime: 0, endTime: 1), toSession: sessionId)
        try await documents.create(DocumentSnapshot(title: "D", fileName: "d.txt", fileType: .txt,
                                                    textContent: "document body text"))
        try await chunks.insert([ChunkSnapshot(sourceId: sessionId, sourceType: .session, text: "chunk",
                                               embedding: VectorPacking.pack([1, 0]), chunkIndex: 0)])

        let audioStore = tempAudioStore()
        try Data(repeating: 9, count: 256).write(to: audioStore.prepareURL(for: sessionId))

        let service = DefaultStorageUsageService(sessions: sessions, documents: documents,
                                                 chunks: chunks, audioStore: audioStore)
        let usage = try await service.usage()
        #expect(usage.sessionsBytes == Int64("hello world".utf8.count))
        #expect(usage.documentsBytes == Int64("document body text".utf8.count))
        #expect(usage.indexBytes == Int64("chunk".utf8.count) + 8)   // 2 floats = 8 bytes
        #expect(usage.audioBytes == 256)
        #expect(usage.totalBytes == usage.sessionsBytes + usage.documentsBytes + usage.indexBytes + 256)
    }

    @Test func wipeRemovesEverything() async throws {
        let (sessions, documents, chunks, chat) = try makeStack()
        let sessionId = UUID()
        try await sessions.create(SessionSnapshot(id: sessionId, title: "S"))
        try await sessions.appendSegment(SegmentSnapshot(sessionId: sessionId, text: "x", startTime: 0, endTime: 1), toSession: sessionId)
        try await documents.create(DocumentSnapshot(title: "D", fileName: "d.txt", fileType: .txt, textContent: "t"))
        try await chunks.insert([ChunkSnapshot(sourceId: sessionId, sourceType: .session, text: "c", chunkIndex: 0)])
        try await chat.append(ChatMessageSnapshot(conversationId: UUID(), role: .user, content: "hi"))

        let audioStore = tempAudioStore()
        try Data(repeating: 1, count: 64).write(to: audioStore.prepareURL(for: sessionId))
        #expect(audioStore.exists(sessionId))

        let wipe = DefaultDataWipeService(sessions: sessions, documents: documents,
                                          chunks: chunks, chat: chat, audioStore: audioStore)
        try await wipe.deleteAllData()

        #expect(try await sessions.fetchAll().isEmpty)
        #expect(try await documents.fetchAll().isEmpty)
        #expect(try await chunks.fetchAll().isEmpty)
        #expect(try await chat.messages(conversationId: UUID()).isEmpty)
        #expect(audioStore.exists(sessionId) == false)   // P17: audio wiped too
    }

    @Test func exportProducesFilePerSession() async throws {
        let (sessions, documents, _, _) = try makeStack()
        try await sessions.create(SessionSnapshot(title: "Meeting One"))
        try await sessions.create(SessionSnapshot(title: "Meeting Two"))
        try await documents.create(DocumentSnapshot(title: "Doc", fileName: "d.txt", fileType: .txt, textContent: "body"))

        let urls = try await DefaultDataExportService(sessions: sessions, documents: documents).exportAll()
        #expect(urls.count == 3)   // 2 sessions + documents-list.md
        #expect(urls.contains { $0.lastPathComponent == "documents-list.md" })
    }
}
