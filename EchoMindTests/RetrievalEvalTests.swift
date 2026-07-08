import Testing
import Foundation
@testable import EchoMind

@Suite struct RetrievalEvalTests {
    /// The measured gate: with the real NLEmbedding sentence embedder, relevant
    /// handbook chunks must land in top-3 for most queries. If this drops, that's
    /// the signal to invest in a MiniLM Core ML embedding (V2 §B1).
    @Test func handbookRetrievalMeetsThreshold() async throws {
        let eval = RetrievalEval(embedder: NLEmbeddingService(), search: VectorSearch())
        let suite = RetrievalEval.handbookSuite()
        #expect(!suite.chunks.isEmpty)

        let result = try await eval.score(chunks: suite.chunks, cases: suite.cases, k: 3)
        // NLEmbedding sentence vectors comfortably clear this on the handbook.
        #expect(result.score >= 0.6, "retrieval score \(result.hits)/\(result.total); misses: \(result.misses)")
    }
}
