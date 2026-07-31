import Foundation

/// Pure scoring refinements over Reciprocal Rank Fusion (RAG 2.0, RAGFlow-style
/// reranking scaled for a phone: no cross-encoder, no extra model call — cheap
/// deterministic priors that TIE-BREAK the fusion order rather than dominate it).
///
/// RRF calibration (k = 60): rank 1 in both rankings ≈ 0.0328, rank 1 in one
/// ≈ 0.0164, rank 10 in one ≈ 0.0143. The boosts below max out around 0.004 —
/// an order below the gap between fusion ranks — so relevance decides and
/// recency/coverage only reorder near-ties.
nonisolated enum RetrievalScoring {
    /// Max boost for a brand-new chunk; decays with age (half-life ~31 days).
    static let recencyWeight = 0.004
    /// Max boost when every query term appears in the chunk.
    static let coverageWeight = 0.004
    /// Weak-retrieval cosine floor: below this best similarity, the corpus has no
    /// semantically close chunk (NLEmbedding-calibrated; unrelated text ~0.0–0.2).
    static let weakCosineFloor: Float = 0.30

    /// Fused score + gentle recency prior + query-term coverage.
    static func adjusted(fused: Double, createdAt: Date, now: Date, coverage: Double) -> Double {
        let ageDays = max(0, now.timeIntervalSince(createdAt)) / 86_400
        let recency = recencyWeight * exp(-ageDays / 45.0)
        return fused + recency + coverageWeight * min(max(coverage, 0), 1)
    }

    /// Fraction of query terms (BM25 tokenization) present in the text. 0 when the
    /// query has no usable terms.
    static func coverage(queryTerms: Set<String>, text: String) -> Double {
        guard !queryTerms.isEmpty else { return 0 }
        let docTerms = Set(BM25.tokenize(text))
        let hit = queryTerms.intersection(docTerms).count
        return Double(hit) / Double(queryTerms.count)
    }

    /// True when the first retrieval pass is a genuine miss — the query shares NO
    /// keywords with the corpus (zero BM25 hits) AND the best vector similarity is
    /// below the cosine floor. (Fused-score floors are useless here: the vector
    /// ranking always returns the k nearest chunks, however distant, so RRF scores
    /// look "strong" even for a semantic miss.) This triggers adaptive query
    /// expansion — the pipeline digs deeper only when the data demands it.
    static func isWeak(bestCosine: Float?, bm25Hits: Int) -> Bool {
        bm25Hits == 0 && (bestCosine ?? 0) < weakCosineFloor
    }
}
