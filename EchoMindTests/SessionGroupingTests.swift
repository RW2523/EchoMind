import Testing
import Foundation
import FoundationModels
@testable import EchoMind

private final class RecordingGateway: ModelGateway, @unchecked Sendable {
    let category: MeetingCategory
    var lastInstructions = ""
    init(category: MeetingCategory) { self.category = category }

    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String { "" }
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T {
        lastInstructions = instructions
        return category as! T
    }
}

private struct StubEmbedder: EmbeddingService {
    let dim: Int
    var dimension: Int { get async throws { dim } }
    func embed(_ texts: [String]) async throws -> [[Float]] { texts.map { _ in [Float](repeating: 0, count: dim) } }
    func prepareAssets() async throws {}
}

private struct StubClassifier: MeetingClassifying {
    func classify(overview: String, existingName: String?) async throws -> MeetingCategory {
        if let existingName, !existingName.isEmpty { return MeetingCategory(category: existingName) }
        return MeetingCategory(category: overview.contains("alpha") ? "Alpha Sync" : "Beta Review", topics: [])
    }
}

@Suite struct MeetingClassifierTests {
    @Test func returnsClassifiedCategory() async throws {
        let gw = RecordingGateway(category: MeetingCategory(category: "Standup", topics: ["api"]))
        let result = try await MeetingClassifier(gateway: gw).classify(overview: "daily sync", existingName: nil)
        #expect(result.category == "Standup")
        #expect(result.topics == ["api"])
    }

    @Test func existingNameNudgesTheModel() async throws {
        let gw = RecordingGateway(category: MeetingCategory(category: "Weekly Sync"))
        _ = try await MeetingClassifier(gateway: gw).classify(overview: "x", existingName: "Weekly Sync")
        #expect(gw.lastInstructions.contains("Weekly Sync"))
    }
}

@Suite struct SessionGroupingTests {
    private func makeStack() throws -> (SwiftDataSessionRepository, SwiftDataChunkRepository) {
        let container = try ModelContainerFactory.inMemory()
        return (SwiftDataSessionRepository(modelContainer: container),
                SwiftDataChunkRepository(modelContainer: container))
    }

    private func addSession(_ repo: SwiftDataSessionRepository, _ chunks: SwiftDataChunkRepository,
                            id: UUID, overview: String, vector: [Float]) async throws {
        try await repo.create(SessionSnapshot(id: id, title: "Meeting"))
        let summary = MeetingSummary(overview: overview)
        try await repo.setReport(summaryJSON: String(decoding: try JSONEncoder().encode(summary), as: UTF8.self),
                                 sessionId: id)
        try await chunks.insert([ChunkSnapshot(sourceId: id, sourceType: .session, text: overview,
                                               embedding: VectorPacking.pack(vector), chunkIndex: 0)])
    }

    @Test func groupsSimilarSessionsAndSeparatesDifferent() async throws {
        let (repo, chunks) = try makeStack()
        let a1 = UUID(), a2 = UUID(), b1 = UUID()
        try await addSession(repo, chunks, id: a1, overview: "project alpha planning", vector: [1, 0, 0, 0])
        try await addSession(repo, chunks, id: a2, overview: "project alpha status", vector: [1, 0, 0, 0])
        try await addSession(repo, chunks, id: b1, overview: "beta launch review", vector: [0, 1, 0, 0])

        let service = SessionGroupingService(sessions: repo, chunks: chunks,
                                             embedder: StubEmbedder(dim: 4), classifier: StubClassifier())
        await service.organize()

        let cat = { (id: UUID) async -> String in (try? await repo.fetchSession(id: id))?.tags.first ?? "" }
        let ca1 = await cat(a1), ca2 = await cat(a2), cb1 = await cat(b1)
        #expect(!ca1.isEmpty)
        #expect(ca1 == ca2)          // same cluster → same category
        #expect(cb1 != ca1)          // different concept → different category
    }

    @Test func newSessionInheritsClusterCanonicalName() async throws {
        let (repo, chunks) = try makeStack()
        let a1 = UUID(), a2 = UUID()
        try await addSession(repo, chunks, id: a1, overview: "project alpha planning", vector: [1, 0, 0, 0])
        let service = SessionGroupingService(sessions: repo, chunks: chunks,
                                             embedder: StubEmbedder(dim: 4), classifier: StubClassifier())
        await service.organize()
        let firstName = (try await repo.fetchSession(id: a1))?.tags.first ?? ""

        // A new, similar, untagged session joins the cluster and inherits the name.
        try await addSession(repo, chunks, id: a2, overview: "project alpha retro", vector: [1, 0, 0, 0])
        await service.organize()
        #expect(try await repo.fetchSession(id: a2)?.tags.first == firstName)
        // The already-labelled session keeps its name (no churn).
        #expect(try await repo.fetchSession(id: a1)?.tags.first == firstName)
    }
}
