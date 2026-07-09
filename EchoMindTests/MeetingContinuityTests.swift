import Testing
import Foundation
import FoundationModels
@testable import EchoMind

private struct StubContinuityGateway: ModelGateway {
    let notes: [String]
    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String { "" }
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type) async throws -> T {
        ContinuityNotes(notes: notes) as! T
    }
}

private struct StubDimEmbedder: EmbeddingService {
    let dim: Int
    var dimension: Int { get async throws { dim } }
    func embed(_ texts: [String]) async throws -> [[Float]] { texts.map { _ in [Float](repeating: 0, count: dim) } }
    func prepareAssets() async throws {}
}

@Suite struct MeetingContinuityTests {
    private func makeStack() throws -> (SwiftDataSessionRepository, SwiftDataChunkRepository) {
        let container = try ModelContainerFactory.inMemory()
        return (SwiftDataSessionRepository(modelContainer: container),
                SwiftDataChunkRepository(modelContainer: container))
    }

    private func addSession(_ repo: SwiftDataSessionRepository, _ chunks: SwiftDataChunkRepository,
                            id: UUID, createdAt: Date, overview: String, vector: [Float]) async throws {
        try await repo.create(SessionSnapshot(id: id, title: "Meeting", createdAt: createdAt))
        let summary = MeetingSummary(overview: overview)
        try await repo.setReport(summaryJSON: String(decoding: try JSONEncoder().encode(summary), as: UTF8.self),
                                 sessionId: id)
        try await chunks.insert([ChunkSnapshot(sourceId: id, sourceType: .session, text: overview,
                                               embedding: VectorPacking.pack(vector), chunkIndex: 0)])
    }

    @Test func linksToPriorSimilarMeeting() async throws {
        let (repo, chunks) = try makeStack()
        let prior = UUID(), current = UUID()
        try await addSession(repo, chunks, id: prior, createdAt: Date(timeIntervalSince1970: 100),
                             overview: "we decided to ship Friday", vector: [1, 0, 0, 0])
        try await addSession(repo, chunks, id: current, createdAt: Date(timeIntervalSince1970: 200),
                             overview: "the ship date slipped to Monday", vector: [1, 0, 0, 0])

        let service = MeetingContinuityService(
            sessions: repo, chunks: chunks, embedder: StubDimEmbedder(dim: 4),
            gateway: StubContinuityGateway(notes: ["Follow-up: ship date moved from Friday to Monday"]))
        let notes = await service.continuityNotes(for: current, overview: "the ship date slipped to Monday")
        #expect(notes == ["Follow-up: ship date moved from Friday to Monday"])
    }

    @Test func noNotesForFirstMeeting() async throws {
        let (repo, chunks) = try makeStack()
        let only = UUID()
        try await addSession(repo, chunks, id: only, createdAt: Date(timeIntervalSince1970: 100),
                             overview: "kickoff", vector: [1, 0, 0, 0])
        let service = MeetingContinuityService(
            sessions: repo, chunks: chunks, embedder: StubDimEmbedder(dim: 4),
            gateway: StubContinuityGateway(notes: ["should not appear"]))
        #expect(await service.continuityNotes(for: only, overview: "kickoff").isEmpty)
    }

    @Test func ignoresUnrelatedPriorMeetings() async throws {
        let (repo, chunks) = try makeStack()
        let prior = UUID(), current = UUID()
        try await addSession(repo, chunks, id: prior, createdAt: Date(timeIntervalSince1970: 100),
                             overview: "gardening club", vector: [0, 1, 0, 0])   // orthogonal → dissimilar
        try await addSession(repo, chunks, id: current, createdAt: Date(timeIntervalSince1970: 200),
                             overview: "engineering roadmap", vector: [1, 0, 0, 0])
        let service = MeetingContinuityService(
            sessions: repo, chunks: chunks, embedder: StubDimEmbedder(dim: 4),
            gateway: StubContinuityGateway(notes: ["should not appear"]))
        #expect(await service.continuityNotes(for: current, overview: "engineering roadmap").isEmpty)
    }

    @Test func continuityPersistsAndDecodes() async throws {
        let (repo, _) = try makeStack()
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "M"))
        let notes = ["Follow-up from last week", "Decision reversed"]
        try await repo.setContinuity(String(decoding: try JSONEncoder().encode(notes), as: UTF8.self), sessionId: id)
        #expect(try await repo.fetchSession(id: id)?.continuityNotes == notes)
    }
}
