import Testing
import Foundation
import FoundationModels
@testable import EchoMind

private func fact(_ text: String, _ kind: MemoryFactKind = .general, at t: TimeInterval) -> MemoryFactSnapshot {
    MemoryFactSnapshot(id: UUID(), kind: kind, text: text, sourceSessionId: nil,
                       updatedAt: Date(timeIntervalSince1970: t))
}

@Suite struct MemoryStoreTests {
    private func store() throws -> SwiftDataMemoryStore {
        SwiftDataMemoryStore(modelContainer: try ModelContainerFactory.inMemory())
    }

    @Test func addsAndFetchesNewestFirst() async throws {
        let store = try store()
        try await store.add([fact("Sam leads design", .person, at: 100)])
        try await store.add([fact("Phoenix ships Q3", .project, at: 200)])
        let all = try await store.all()
        #expect(all.count == 2)
        #expect(all.first?.text == "Phoenix ships Q3")   // newest first
    }

    @Test func addDeduplicatesAgainstStoredFacts() async throws {
        let store = try store()
        try await store.add([fact("Sam leads design", .person, at: 100)])
        // Same fact re-distilled from a later meeting (different casing/whitespace).
        try await store.add([fact("  sam LEADS design ", .person, at: 300)])
        let all = try await store.all()
        #expect(all.count == 1)                                  // no duplicate row
        #expect(all.first?.updatedAt == Date(timeIntervalSince1970: 300))   // recency refreshed
    }

    @Test func addDeduplicatesWithinBatch() async throws {
        let store = try store()
        try await store.add([fact("Phoenix ships Q3", .project, at: 10),
                             fact("phoenix ships q3", .project, at: 20)])
        #expect(try await store.count() == 1)
    }

    @Test func retireMatchesCaseInsensitively() async throws {
        let store = try store()
        try await store.add([fact("Sam leads design", .person, at: 100)])
        try await store.retire(matching: ["  sam LEADS design "])
        #expect(try await store.count() == 0)
    }

    @Test func deleteByIdRemovesOne() async throws {
        let store = try store()
        let f = fact("keep me", at: 1)
        try await store.add([f, fact("delete me", at: 2)])
        let toDelete = try await store.all().first { $0.text == "delete me" }!
        try await store.delete(id: toDelete.id)
        #expect(try await store.all().map(\.text) == ["keep me"])
    }

    @Test func pruneKeepsNewest() async throws {
        let store = try store()
        for i in 0..<5 { try await store.add([fact("f\(i)", at: TimeInterval(i))]) }
        try await store.prune(max: 3)
        let all = try await store.all()
        #expect(all.count == 3)
        #expect(all.map(\.text) == ["f4", "f3", "f2"])
    }

    @Test func deleteAllEmptiesStore() async throws {
        let store = try store()
        try await store.add([fact("a", at: 1), fact("b", at: 2)])
        try await store.deleteAll()
        #expect(try await store.count() == 0)
    }
}

private struct StubMemoryGateway: ModelGateway {
    let update: MemoryUpdate
    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String { "" }
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T {
        update as! T
    }
}

@Suite struct MemoryDistillerTests {
    private func store() throws -> SwiftDataMemoryStore {
        SwiftDataMemoryStore(modelContainer: try ModelContainerFactory.inMemory())
    }

    @Test func addsNewFactsAndRetiresOld() async throws {
        let store = try store()
        try await store.add([fact("old plan: launch in June", .decision, at: 1)])
        let update = MemoryUpdate(add: [MemoryFactDraft(kind: "decision", text: "launch moved to August")],
                                  retire: ["old plan: launch in June"])
        let distiller = MemoryDistiller(gateway: StubMemoryGateway(update: update), store: store)
        await distiller.distill(reportOverview: "we moved the launch", sessionId: UUID())

        let texts = try await store.all().map(\.text)
        #expect(texts.contains("launch moved to August"))
        #expect(!texts.contains("old plan: launch in June"))
    }

    @Test func skipsEmptyOverview() async throws {
        let store = try store()
        try await store.add([fact("existing", at: 1)])
        let distiller = MemoryDistiller(gateway: StubMemoryGateway(update: MemoryUpdate(add: [MemoryFactDraft(text: "should not appear")])),
                                        store: store)
        await distiller.distill(reportOverview: "   ", sessionId: UUID())
        #expect(try await store.count() == 1)   // unchanged
    }

    @Test func prunesToCap() async throws {
        let store = try store()
        let update = MemoryUpdate(add: [MemoryFactDraft(text: "one"),
                                        MemoryFactDraft(text: "two"),
                                        MemoryFactDraft(text: "three")])
        var distiller = MemoryDistiller(gateway: StubMemoryGateway(update: update), store: store)
        distiller.maxFacts = 2
        await distiller.distill(reportOverview: "lots happened", sessionId: UUID())
        #expect(try await store.count() == 2)
    }
}

@Suite struct MemoryPreambleTests {
    @Test func buildsBulletedBlock() {
        let out = MemoryPreamble.build(from: ["Sam leads design", "Phoenix ships Q3"],
                                       budgeter: TokenBudgeter(), maxTokens: 1000)
        #expect(out.contains("- Sam leads design"))
        #expect(out.contains("- Phoenix ships Q3"))
    }

    @Test func dropsFactsBeyondBudget() {
        let facts = (0..<50).map { "fact number \($0) with some words" }
        let out = MemoryPreamble.build(from: facts, budgeter: TokenBudgeter(), maxTokens: 20)
        #expect(out.split(separator: "\n").count < facts.count)   // truncated to budget
    }

    @Test func emptyForNoFacts() {
        #expect(MemoryPreamble.build(from: [], budgeter: TokenBudgeter(), maxTokens: 100).isEmpty)
    }
}
