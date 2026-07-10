import Testing
import Foundation
@testable import EchoMind

@Suite struct RetrievalEvalTests {
    /// The measured gate: with the real NLEmbedding sentence embedder, relevant
    /// handbook chunks must land in top-3 for most queries. If this drops, that's
    /// the signal to invest in a MiniLM Core ML embedding (V2 §B1).
    @Test func handbookRetrievalMeetsThreshold() async throws {
        guard await EmbeddingTestSupport.modelAvailable() else { return }   // no asset on CI
        let eval = RetrievalEval(embedder: NLEmbeddingService(), search: VectorSearch())
        let suite = RetrievalEval.handbookSuite()
        #expect(!suite.chunks.isEmpty)

        let result = try await eval.score(chunks: suite.chunks, cases: suite.cases, k: 3)
        // NLEmbedding sentence vectors comfortably clear this on the handbook.
        #expect(result.score >= 0.6, "retrieval score \(result.hits)/\(result.total); misses: \(result.misses)")
    }

    /// P16 ship gate: MMR diversity reranking must not regress handbook recall.
    /// (Its measurable *win* — surfacing diverse passages over near-duplicates — is
    /// proven deterministically in MMRRerankerTests; here we prove it's safe on real
    /// embeddings before shipping it in the pipeline.)
    @Test func mmrRerankDoesNotRegressHandbookRecall() async throws {
        guard await EmbeddingTestSupport.modelAvailable() else { return }   // no asset on CI
        let eval = RetrievalEval(embedder: NLEmbeddingService(), search: VectorSearch())
        let suite = RetrievalEval.handbookSuite()
        let plain = try await eval.score(chunks: suite.chunks, cases: suite.cases, k: 3)
        let reranked = try await eval.score(chunks: suite.chunks, cases: suite.cases, k: 3,
                                            reranker: MMRReranker(lambda: RAGPipeline.mmrLambda))
        #expect(reranked.score >= plain.score,
                "MMR regressed recall: \(reranked.hits)/\(reranked.total) vs plain \(plain.hits)/\(plain.total)")
    }
}
