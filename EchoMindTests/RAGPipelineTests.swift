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

    @Test func emptyKnowledgeAnswersConversationallyWithFollowUps() async throws {
        let (chunks, _) = try makeChunks()
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "Hi there!", usedProvidedContext: false, followUps: ["What can you do?"]))
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("Hi", history: [])
        if case .conversational(let answer, let followUps) = result {
            #expect(answer == "Hi there!")
            #expect(followUps == ["What can you do?"])
        } else {
            Issue.record("expected conversational, got \(result)")
        }
    }

    @Test func groundedWhenModelUsesContext() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["The refund policy is 30 days."])
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "30 days.", usedProvidedContext: true, followUps: ["What about digital goods?"]))
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("refund policy?", history: [])
        if case .grounded(let answer, let sources, let followUps) = result {
            #expect(answer == "30 days.")
            #expect(sources.count == 1)
            #expect(followUps.count == 1)
        } else {
            Issue.record("expected grounded, got \(result)")
        }
    }

    @Test func conversationalWhenContextIrrelevant() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Unrelated meeting notes."])
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "Hello!", usedProvidedContext: false))
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("Hi", history: [])
        if case .conversational = result {} else { Issue.record("expected conversational, got \(result)") }
    }

    @Test func historyTriggersQueryRewrite() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Passage."])
        let gateway = MockModelGateway()
        _ = try await pipeline(chunks: chunks, gateway: gateway).ask(
            "and who owns it?",
            history: [ChatTurn(role: .user, content: "what is the billing migration?"),
                      ChatTurn(role: .assistant, content: "It moves to Q3.")])
        // The rewrite step is one respond() call before the guided answer.
        #expect(await gateway.counts().respond == 1)
    }

    @Test func tierBReturnsRetrievalOnly() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Some passage."])
        let result = try await pipeline(chunks: chunks, gateway: MockModelGateway(),
                                        availability: { .tierB(.appleIntelligenceNotEnabled) }).ask("hi", history: [])
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
        let gateway = MockModelGateway(overflowGenerate: 2)
        let result = try await pipeline(chunks: chunks, gateway: gateway).ask("question", history: [])
        if case .retrievalOnly(_, let reason) = result {
            #expect(reason == .contextOverflow)
        } else {
            Issue.record("expected retrievalOnly(contextOverflow), got \(result)")
        }
        #expect(await gateway.counts().generate == 2)
    }

    @Test func overLongQuestionRejectedBeforeModelCall() async throws {
        let (chunks, _) = try makeChunks()
        try await seed(chunks, texts: ["Passage."])
        let longQuestion = String(repeating: "word ", count: 600)
        await #expect(throws: RAGError.questionTooLong) {
            _ = try await self.pipeline(chunks: chunks, gateway: MockModelGateway()).ask(longQuestion, history: [])
        }
    }

    @Test func memoryFormatsRecentTurns() {
        let memory = RAGPipeline.memory(from: [
            ChatTurn(role: .user, content: "hi"),
            ChatTurn(role: .assistant, content: "hello"),
        ])
        #expect(memory == "User: hi\nAssistant: hello")
    }
}
