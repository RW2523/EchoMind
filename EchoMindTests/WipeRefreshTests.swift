import Testing
import Foundation
import SwiftData
@testable import EchoMind

// Field bugs from live end-to-end testing: after Delete All Data the Ask
// thread kept its in-memory messages (stale history then fed the next
// question), and with nothing retrieved the model invented a document
// inventory from chat history.

private nonisolated struct StubRAGService: RAGService {
    func ask(_ question: String, history: [ChatTurn]) async throws -> AskResult {
        .conversational(answer: "ok", followUps: [])
    }
}

@MainActor
@Suite struct WipeRefreshTests {
    @Test func dataWipeNotificationClearsAskThread() async throws {
        let container = try ModelContainerFactory.inMemory()
        let chat = SwiftDataChatRepository(modelContainer: container)
        let model = AskViewModel(rag: StubRAGService(), chat: chat,
                                 chunks: SwiftDataChunkRepository(modelContainer: container),
                                 documents: SwiftDataDocumentRepository(modelContainer: container),
                                 sessions: SwiftDataSessionRepository(modelContainer: container))
        model.draft = "hello"
        await model.send()
        #expect(!model.messages.isEmpty)

        NotificationCenter.default.post(name: .echoMindDataWiped, object: nil)
        // The observer runs on the main actor; give it a few turns to fire.
        for _ in 0..<50 where !model.messages.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.messages.isEmpty)
    }
}

@Suite struct EmptyCorpusHonestyTests {
    @Test func savedKnowledgeQuestionShortCircuitsToNotFound() async throws {
        // The confabulated-inventory field bug: this must never reach the model.
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)   // empty corpus
        let embedder = MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] })
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "You have two documents.", usedProvidedContext: false))
        let pipeline = RAGPipeline(corpus: CorpusCache(chunks: chunks, dimension: { try await embedder.dimension }),
                                   embedder: embedder, search: VectorSearch(),
                                   gateway: gateway, budgeter: TokenBudgeter(), availability: { .tierA })
        let history = [ChatTurn(role: .user, content: "what documents do I have?"),
                       ChatTurn(role: .assistant, content: "You have two documents.")]
        let result = try await pipeline.ask("what documents do I have saved?", history: history)
        guard case .notFound(let answer, _) = result else {
            Issue.record("expected notFound, got \(result)"); return
        }
        #expect(answer.contains("couldn't find"))
        #expect(await gateway.counts().generate == 0)      // no model call at all
    }

    @Test func mentionsSavedKnowledgePatterns() {
        #expect(RAGPipeline.mentionsSavedKnowledge("What documents do I have saved?"))
        #expect(RAGPipeline.mentionsSavedKnowledge("what's in my documents?"))
        #expect(RAGPipeline.mentionsSavedKnowledge("summarize my meetings"))
        #expect(!RAGPipeline.mentionsSavedKnowledge("Hi"))
        #expect(!RAGPipeline.mentionsSavedKnowledge("can you take notes for me?"))
        #expect(!RAGPipeline.mentionsSavedKnowledge("what is a vector database?"))
    }

    @Test func emptyRetrievalInjectsTheNotice() async throws {
        // A non-catalog question against an empty corpus still reaches the
        // model — but the prompt must carry the empty-context notice.
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)   // empty corpus
        let embedder = MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] })
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "I couldn't find that in your knowledge.",
                                       usedProvidedContext: false, notFoundInContext: true))
        let pipeline = RAGPipeline(corpus: CorpusCache(chunks: chunks, dimension: { try await embedder.dimension }),
                                   embedder: embedder, search: VectorSearch(),
                                   gateway: gateway, budgeter: TokenBudgeter(), availability: { .tierA })
        _ = try await pipeline.ask("tell me about the falcon dataset", history: [])
        let prompt = await gateway.lastGeneratePrompt
        #expect(prompt?.contains("No passages were found") == true)
        #expect(prompt?.contains("NEVER invent") == true)
    }

    @Test func nonEmptyRetrievalDoesNotInjectTheNotice() async throws {
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        try await chunks.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .document,
                                               text: "The dataset has 5,800 clips.",
                                               embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        let embedder = MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] })
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "It has 5,800 clips.", usedProvidedContext: true))
        let pipeline = RAGPipeline(corpus: CorpusCache(chunks: chunks, dimension: { try await embedder.dimension }),
                                   embedder: embedder, search: VectorSearch(),
                                   gateway: gateway, budgeter: TokenBudgeter(), availability: { .tierA })
        _ = try await pipeline.ask("how many clips?", history: [])
        let prompt = await gateway.lastGeneratePrompt
        #expect(prompt?.contains("No passages were found") == false)
        #expect(prompt?.contains("5,800") == true)
    }
}
