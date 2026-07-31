import Foundation

/// The hybrid retrieval engine (RAG 2.0 — RAGFlow's retrieval ideas scaled for a
/// phone): cached corpus → vector ∪ BM25 → Reciprocal Rank Fusion → recency +
/// term-coverage adjustment → MMR diversity → top-K. Adaptive depth: when the
/// first pass is weak, an optional expansion provider (one model call) supplies
/// paraphrases whose rankings are fused in — the pipeline digs deeper only when
/// the data demands it. Pure vDSP math over the in-memory corpus; no extra model
/// calls on the happy path.
nonisolated struct HybridRetriever: Sendable {
    let corpus: CorpusCache
    let embedder: any EmbeddingService
    let search: VectorSearch
    /// Multi-query expansion, consulted ONLY when retrieval is weak.
    var expand: (@Sendable (String) async -> [String])?

    static let fusionPoolK = 20
    static let mmrPoolK = 12
    static let mmrLambda: Float = 0.7

    func retrieve(_ query: String, k: Int, now: Date = Date()) async throws -> [RetrievedChunk] {
        let entries = try await corpus.corpus()
        guard !entries.isEmpty else { return [] }
        guard let primaryVector = try await embedder.embed([query]).first else { return [] }

        let vectorCandidates = entries.compactMap { entry in
            entry.vector.map { (id: entry.id, vector: $0) }
        }
        // Primary pass, keeping the raw signals the weakness detector needs.
        let vectorHits = search.topK(query: primaryVector, candidates: vectorCandidates,
                                     k: Self.fusionPoolK)
        let bm25Hits = BM25().rank(query: query,
                                   documents: entries.map { (id: $0.id, text: $0.text) },
                                   k: Self.fusionPoolK)
        var rankings = [vectorHits.map(\.id), bm25Hits.map(\.id)]
        var fused = Self.adjustedFusion(rankings: rankings, entries: entries, query: query, now: now)

        // Genuine miss (no keyword overlap + low best similarity) → expand the
        // query into paraphrases and fuse ALL rankings.
        if RetrievalScoring.isWeak(bestCosine: vectorHits.first?.score, bm25Hits: bm25Hits.count),
           let expand {
            for alternative in await expand(query).prefix(2) {
                let alt = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !alt.isEmpty, alt.lowercased() != query.lowercased() else { continue }
                guard let altVector = try? await embedder.embed([alt]).first else { continue }
                rankings += rankPair(query: alt, queryVector: altVector,
                                     entries: entries, vectorCandidates: vectorCandidates)
            }
            fused = Self.adjustedFusion(rankings: rankings, entries: entries, query: query, now: now)
        }

        let ordered = mmrOrder(fused: fused, queryVector: primaryVector,
                               vectors: vectorCandidates, k: k)
        let entryById = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scoreById = Dictionary(fused.map { ($0.id, $0.score) }, uniquingKeysWith: { first, _ in first })
        return ordered.compactMap { id in
            entryById[id].map {
                RetrievedChunk(chunk: Self.snapshot(from: $0), score: Float(scoreById[id] ?? 0))
            }
        }
    }

    // MARK: - Ranking

    /// One query's pair of rankings (vector similarity + BM25 keywords).
    private func rankPair(query: String, queryVector: [Float],
                          entries: [CorpusCache.Entry],
                          vectorCandidates: [(id: UUID, vector: [Float])]) -> [[UUID]] {
        let vectorRanking = search.topK(query: queryVector, candidates: vectorCandidates,
                                        k: Self.fusionPoolK).map(\.id)
        let bm25Ranking = BM25().rank(query: query,
                                      documents: entries.map { (id: $0.id, text: $0.text) },
                                      k: Self.fusionPoolK).map(\.id)
        return [vectorRanking, bm25Ranking]
    }

    /// RRF over all rankings, then the cheap deterministic priors: a gentle recency
    /// boost and query-term coverage — tie-breakers, never dominant (RetrievalScoring).
    static func adjustedFusion(rankings: [[UUID]], entries: [CorpusCache.Entry],
                               query: String, now: Date) -> [(id: UUID, score: Double)] {
        let fused = BM25.reciprocalRankFusion(rankings)
        let entryById = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let queryTerms = Set(BM25.tokenize(query))
        let adjusted = fused.map { item -> (id: UUID, score: Double) in
            guard let entry = entryById[item.id] else { return item }
            let coverage = RetrievalScoring.coverage(queryTerms: queryTerms, text: entry.text)
            return (item.id, RetrievalScoring.adjusted(fused: item.score, createdAt: entry.createdAt,
                                                       now: now, coverage: coverage))
        }
        return adjusted.sorted { $0.score > $1.score }
    }

    /// MMR-rerank the fused pool for diversity, then take `k`. Fused candidates
    /// without a usable vector (BM25-only keyword hits) are appended in fused order
    /// so exact matches are never dropped by the diversity pass.
    private func mmrOrder(fused: [(id: UUID, score: Double)], queryVector: [Float],
                          vectors: [(id: UUID, vector: [Float])], k: Int) -> [UUID] {
        let pool = Array(fused.prefix(Self.mmrPoolK))
        let vecById = Dictionary(vectors.map { ($0.id, $0.vector) }, uniquingKeysWith: { first, _ in first })
        let mmrInput = pool.compactMap { item in vecById[item.id].map { (id: item.id, vector: $0) } }
        guard mmrInput.count >= 2 else { return pool.prefix(k).map(\.id) }

        var picked = MMRReranker(lambda: Self.mmrLambda)
            .rerank(query: queryVector, candidates: mmrInput, k: k)
        var seen = Set(picked)
        for item in pool where !seen.contains(item.id) {
            guard picked.count < k else { break }
            picked.append(item.id)
            seen.insert(item.id)
        }
        return picked
    }

    /// Entry → the snapshot shape `RetrievedChunk` carries (embedding omitted —
    /// nothing downstream reads it, and duplicating vectors would double memory).
    static func snapshot(from entry: CorpusCache.Entry) -> ChunkSnapshot {
        ChunkSnapshot(id: entry.id, sourceId: entry.sourceId, sourceType: entry.sourceType,
                      text: entry.text, embedding: Data(), chunkIndex: 0,
                      createdAt: entry.createdAt)
    }
}
