import Testing
import Foundation
import SwiftData
@testable import EchoMind

@Suite struct StorageTests {

    @Test func createAndFetchRoundTrip() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "Standup", duration: 120,
                                              origin: .live, tags: ["team"]))
        let fetched = try await repo.fetchSession(id: id)
        #expect(fetched?.title == "Standup")
        #expect(fetched?.duration == 120)
        #expect(fetched?.origin == .live)
        #expect(fetched?.tags == ["team"])
    }

    @Test func fetchAllSortedByCreatedAtDescending() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let older = SessionSnapshot(title: "Older", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = SessionSnapshot(title: "Newer", createdAt: Date(timeIntervalSince1970: 2_000))
        try await repo.create(older)
        try await repo.create(newer)
        let all = try await repo.fetchAll()
        #expect(all.map(\.title) == ["Newer", "Older"])
    }

    @Test func cascadeDeleteRemovesSegments() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "T"))
        try await repo.appendSegment(SegmentSnapshot(sessionId: id, text: "a", startTime: 0, endTime: 1), toSession: id)
        try await repo.appendSegment(SegmentSnapshot(sessionId: id, text: "b", startTime: 1, endTime: 2), toSession: id)
        #expect(try await repo.fetchSegments(sessionId: id).count == 2)

        try await repo.delete(id: id)
        #expect(try await repo.fetchAll().isEmpty)
        // Fresh context confirms segments are gone from the store, not just cached.
        let verify = SwiftDataSessionRepository(modelContainer: container)
        #expect(try await verify.fetchSegments(sessionId: id).isEmpty)
    }

    @Test func segmentsReturnInStartTimeOrder() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "T"))
        try await repo.appendSegment(SegmentSnapshot(sessionId: id, text: "second", startTime: 5, endTime: 6), toSession: id)
        try await repo.appendSegment(SegmentSnapshot(sessionId: id, text: "first", startTime: 0, endTime: 1), toSession: id)
        let segments = try await repo.fetchSegments(sessionId: id)
        #expect(segments.map(\.text) == ["first", "second"])
    }

    @Test func appendSegmentToMissingSessionThrows() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        await #expect(throws: StorageError.sessionNotFound) {
            try await repo.appendSegment(
                SegmentSnapshot(sessionId: UUID(), text: "x", startTime: 0, endTime: 1),
                toSession: UUID())
        }
    }

    @Test func deletingSessionSweepsItsChunks() async throws {
        let container = try ModelContainerFactory.inMemory()
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let sessionId = UUID()
        let otherId = UUID()
        try await sessions.create(SessionSnapshot(id: sessionId, title: "S"))
        try await chunks.insert([
            ChunkSnapshot(sourceId: sessionId, sourceType: .session, text: "c1", chunkIndex: 0),
            ChunkSnapshot(sourceId: sessionId, sourceType: .session, text: "c2", chunkIndex: 1),
            ChunkSnapshot(sourceId: otherId, sourceType: .document, text: "keep", chunkIndex: 0),
        ])

        try await sessions.delete(id: sessionId)

        let verify = SwiftDataChunkRepository(modelContainer: container)
        let remaining = try await verify.fetchAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.sourceId == otherId)
    }

    @Test func deletingDocumentSweepsItsChunks() async throws {
        let container = try ModelContainerFactory.inMemory()
        let documents = SwiftDataDocumentRepository(modelContainer: container)
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let docId = UUID()
        try await documents.create(DocumentSnapshot(id: docId, title: "D", fileName: "d.pdf",
                                                    fileType: .pdf, textContent: "hello"))
        try await chunks.insert([
            ChunkSnapshot(sourceId: docId, sourceType: .document, text: "c1", chunkIndex: 0),
        ])

        try await documents.delete(id: docId)

        let verify = SwiftDataChunkRepository(modelContainer: container)
        #expect(try await verify.fetchAll().isEmpty)
    }

    @Test func documentStatusUpdatePersists() async throws {
        let container = try ModelContainerFactory.inMemory()
        let documents = SwiftDataDocumentRepository(modelContainer: container)
        let id = UUID()
        try await documents.create(DocumentSnapshot(id: id, title: "D", fileName: "d.md",
                                                    fileType: .md, textContent: "x"))
        try await documents.updateStatus(id: id, status: .ready)
        #expect(try await documents.fetchDocument(id: id)?.status == .ready)
    }

    @MainActor
    @Test func appSettingsFetchOrCreateIsIdempotent() throws {
        let container = try ModelContainerFactory.inMemory()
        let store = AppSettingsStore(container: container)
        #expect(store.onboardingComplete == false)
        store.setOnboardingComplete(true)
        store.setConsentAcknowledged(true)
        #expect(store.onboardingComplete == true)
        #expect(store.consentAcknowledged == true)
        // Repeated access must never create a second row.
        _ = store.onboardingComplete
        _ = store.consentAcknowledged
        let rows = try container.mainContext.fetch(FetchDescriptor<AppSettings>())
        #expect(rows.count == 1)
    }
}
