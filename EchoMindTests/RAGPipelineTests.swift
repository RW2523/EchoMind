import Testing
import Foundation
import SwiftData
@testable import EchoMind

@Suite struct RAGPipelineTests {
    private func makeChunks() throws -> (any ChunkRepository, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        return (SwiftDataChunkRepository(modelContainer: container), container)
    }

    private func seed(_ repo: any ChunkRepository, texts: [String]) async throws {
        let source = UUID()
        var snapshots: [ChunkSnapshot] = []
        for (index, text) in texts.enumerated() {
            snapshots.append(ChunkSnapshot(sourceId: source, sourceType: .document, text: text,
                                           embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: index))
        }
        try await repo.insert(snapshots)
    }

    private func pipeline(chunks: any ChunkRepository, gateway: MockModelGateway,
                          availability: @escaping @Sendable () async -> AvailabilityStatus = { .tierA }) -> RAGPipeline {
        RAGPipeline(chunks: chunks,
                    embedder: MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] }),
                    search: VectorSearch(), gateway: gateway, budgeter: TokenBudgeter(),
                    availability: availability)
    }

    @Test func emptyIndexShortCircuits() async throws {
        let (chunks, _) = try makeChunks()
        let result = try await pipeline(chunks: chunks, gateway: MockModelGateway()).ask("anything")
        #expect(result == .emptyIndex)
    }

    @Test func groundedAnswerCitesSources() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["The refund policy is 30 days."])
        let gateway = MockModelGateway(respondReturn: "The refund policy is 30 days.")
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("refund policy?")
        if case .grounded(let answer, let sources) = result {
            #expect(answer == "The refund policy is 30 days.")
            #expect(sources.count == 1)
            #expect(sources[0].sourceType == .document)
        } else {
            Issue.record("expected grounded, got \(result)")
        }
    }

    @Test func exactNotFoundSentenceMapsToNotFound() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Unrelated content."])
        let gateway = MockModelGateway(respondReturn: RAGPrompts.notFoundSentence)
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("what is the meaning of life?")
        #expect(result == .notFound)
    }

    @Test func tierBReturnsRetrievalOnly() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Some passage."])
        let result = try await pipeline(chunks: chunks, gateway: MockModelGateway(),
                                        availability: { .tierB(.appleIntelligenceNotEnabled) }).ask("hi")
        if case .retrievalOnly(let passages, let reason) = result {
            #expect(passages.count == 1)
            if case .tierB = reason {} else { Issue.record("expected tierB reason") }
        } else {
            Issue.record("expected retrievalOnly, got \(result)")
        }
    }

    @Test func overflowDropsRetriesThenFallsBack() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Passage one.", "Passage two.", "Passage three."])
        // Both the initial answer and the drop-one retry overflow.
        let gateway = MockModelGateway(overflowRespond: 2)
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("question")
        if case .retrievalOnly(_, let reason) = result {
            #expect(reason == .contextOverflow)
        } else {
            Issue.record("expected retrievalOnly(contextOverflow), got \(result)")
        }
        #expect(await gateway.counts().respond == 2)   // initial + one retry
    }

    @Test func overLongQuestionRejectedBeforeModelCall() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Passage."])
        let longQuestion = String(repeating: "word ", count: 600)   // ~857 tokens > 250
        await #expect(throws: RAGError.questionTooLong) {
            _ = try await self.pipeline(chunks: chunks, gateway: MockModelGateway()).ask(longQuestion)
        }
    }
}
