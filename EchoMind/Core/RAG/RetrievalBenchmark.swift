import Foundation

/// Measures retrieval quality with ranked metrics — recall@k and MRR — over a
/// corpus and a set of question / expected-source pairs. Unlike `RetrievalEval`
/// (binary hit@k over pure vector search), this runs the SAME hybrid pipeline the
/// app uses at query time — vector ∪ BM25 → Reciprocal Rank Fusion → MMR — so the
/// numbers reflect what users actually get. The corpus is always re-embedded with
/// the injected embedder, so you can A/B a candidate embedder (NLEmbedding vs a
/// linked EmbeddingGemma) apples-to-apples and decide the upgrade with data.
///
/// The top-6 ordering is identical to `RAGPipeline` (greedy MMR is prefix-stable,
/// and the fusion constants are shared), so recall@6 here is exactly recall over
/// the chunks the model is actually fed.
nonisolated struct RetrievalBenchmark {
    /// One retrievable unit. `sourceId` is the originating session/document, so a
    /// case can be judged relevant by source as well as by text.
    nonisolated struct Doc: Sendable, Equatable {
        let id: UUID
        let sourceId: UUID?
        let text: String
        init(id: UUID = UUID(), sourceId: UUID? = nil, text: String) {
            self.id = id
            self.sourceId = sourceId
            self.text = text
        }
    }

    /// A labelled query. A doc is relevant if its text contains `expectTextContains`
    /// (case-insensitive) OR its `sourceId` equals `expectSourceId`. At least one
    /// expectation should be set.
    nonisolated struct Case: Sendable, Equatable {
        let query: String
        let expectTextContains: String?
        let expectSourceId: UUID?
        init(query: String, expectTextContains: String? = nil, expectSourceId: UUID? = nil) {
            self.query = query
            self.expectTextContains = expectTextContains
            self.expectSourceId = expectSourceId
        }
    }

    nonisolated struct QueryOutcome: Sendable {
        let query: String
        let relevantInCorpus: Int
        /// 1-based rank of the first relevant doc, or nil if none within `evalDepth`.
        let firstRelevantRank: Int?
        /// recall@k for each requested k (nil for a case with no relevant docs).
        let recallAtK: [Int: Double]
        var reciprocalRank: Double { firstRelevantRank.map { 1.0 / Double($0) } ?? 0 }
    }

    nonisolated struct Report: Sendable {
        let embedderName: String
        let corpusSize: Int
        let ks: [Int]
        let perQuery: [QueryOutcome]
        /// Cases whose expected text/source matched nothing in the corpus — label
        /// errors, excluded from the recall means and surfaced so you can fix them.
        let unlabeled: [String]

        /// Mean recall@k over cases that had at least one relevant doc.
        var meanRecallAtK: [Int: Double] {
            let scored = perQuery.filter { $0.relevantInCorpus > 0 }
            guard !scored.isEmpty else { return [:] }
            var out: [Int: Double] = [:]
            for k in ks {
                let vals = scored.compactMap { $0.recallAtK[k] }
                out[k] = vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
            }
            return out
        }

        /// Mean Reciprocal Rank over cases that had at least one relevant doc.
        var mrr: Double {
            let scored = perQuery.filter { $0.relevantInCorpus > 0 }
            guard !scored.isEmpty else { return 0 }
            return scored.map(\.reciprocalRank).reduce(0, +) / Double(scored.count)
        }
    }

    let embedder: any EmbeddingService
    let search: VectorSearch
    /// Which recall@k to report. Include 6 — that's what the app feeds the model.
    let ks: [Int]
    /// How deep to rank when locating the first relevant doc (for MRR).
    let evalDepth: Int

    init(embedder: any EmbeddingService, search: VectorSearch = VectorSearch(),
         ks: [Int] = [1, 3, 6], evalDepth: Int = 20) {
        self.embedder = embedder
        self.search = search
        self.ks = ks.sorted()
        self.evalDepth = evalDepth
    }

    func run(corpus: [Doc], cases: [Case], embedderName: String = "embedder") async throws -> Report {
        guard !corpus.isEmpty, !cases.isEmpty else {
            return Report(embedderName: embedderName, corpusSize: corpus.count, ks: ks, perQuery: [], unlabeled: [])
        }
        let vectors = try await embedder.embed(corpus.map(\.text))
        let candidates = zip(corpus, vectors).map { (id: $0.0.id, vector: $0.1) }
        let documents = corpus.map { (id: $0.id, text: $0.text) }
        let docById = Dictionary(corpus.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var outcomes: [QueryOutcome] = []
        var unlabeled: [String] = []
        for testCase in cases {
            let relevant = Set(corpus.filter { isRelevant($0, to: testCase) }.map(\.id))
            if relevant.isEmpty { unlabeled.append(testCase.query) }

            guard let queryVector = try await embedder.embed([testCase.query]).first else { continue }
            let ranked = rank(query: testCase.query, queryVector: queryVector,
                              candidates: candidates, documents: documents)

            let firstRank = ranked.firstIndex { relevant.contains($0) }.map { $0 + 1 }
            var recall: [Int: Double] = [:]
            if !relevant.isEmpty {
                for k in ks {
                    let hits = ranked.prefix(k).filter { relevant.contains($0) }.count
                    recall[k] = Double(hits) / Double(relevant.count)
                }
            }
            outcomes.append(QueryOutcome(query: testCase.query, relevantInCorpus: relevant.count,
                                         firstRelevantRank: firstRank, recallAtK: recall))
            _ = docById   // (kept for future per-hit reporting)
        }
        return Report(embedderName: embedderName, corpusSize: corpus.count, ks: ks,
                      perQuery: outcomes, unlabeled: unlabeled)
    }

    private func isRelevant(_ doc: Doc, to c: Case) -> Bool {
        if let text = c.expectTextContains, doc.text.localizedCaseInsensitiveContains(text) { return true }
        if let source = c.expectSourceId, doc.sourceId == source { return true }
        return false
    }

    /// The app's hybrid ranking, generalized to return `evalDepth` ids. Mirrors
    /// `RAGPipeline.hybridRetrieve` + `mmrOrder` and reuses its fusion constants, so
    /// the top-`retrieveK` ordering is identical to production (greedy MMR is
    /// prefix-stable), with a fused-order tail for measuring rank beyond the cut.
    private func rank(query: String, queryVector: [Float],
                      candidates: [(id: UUID, vector: [Float])],
                      documents: [(id: UUID, text: String)]) -> [UUID] {
        let vectorRanking = search.topK(query: queryVector, candidates: candidates,
                                        k: RAGPipeline.fusionPoolK).map(\.id)
        let bm25Ranking = BM25().rank(query: query, documents: documents,
                                      k: RAGPipeline.fusionPoolK).map(\.id)
        let fused = BM25.reciprocalRankFusion([vectorRanking, bm25Ranking])
        let fusedIDs = fused.map(\.id)

        let pool = Array(fused.prefix(RAGPipeline.mmrPoolK))
        let vecById = Dictionary(candidates.map { ($0.id, $0.vector) }, uniquingKeysWith: { first, _ in first })
        let mmrInput = pool.compactMap { item in vecById[item.id].map { (id: item.id, vector: $0) } }

        var ordered: [UUID] = []
        var seen = Set<UUID>()
        if mmrInput.count >= 2 {
            // MMR over the pool; greedy MMR's prefix matches production's top-retrieveK.
            let mmr = MMRReranker(lambda: RAGPipeline.mmrLambda)
                .rerank(query: queryVector, candidates: mmrInput, k: min(evalDepth, mmrInput.count))
            for id in mmr where !seen.contains(id) { ordered.append(id); seen.insert(id) }
        }
        // Append any pool items MMR skipped (BM25-only, no vector), then the fused tail.
        for id in fusedIDs where !seen.contains(id) {
            ordered.append(id); seen.insert(id)
            if ordered.count >= evalDepth { break }
        }
        return Array(ordered.prefix(evalDepth))
    }
}

extension RetrievalBenchmark.Report {
    /// Monospace summary for the Xcode console and the in-app debug button.
    nonisolated func formatted() -> String {
        var lines: [String] = []
        lines.append("Retrieval benchmark — \(embedderName)")
        lines.append("corpus: \(corpusSize) chunks · \(perQuery.count) queries")
        let means = meanRecallAtK
        let recallStr = ks.map { "recall@\($0) \(pct(means[$0]))" }.joined(separator: "  ")
        lines.append(recallStr + "   MRR \(fmt(mrr))")
        if !unlabeled.isEmpty {
            lines.append("⚠︎ \(unlabeled.count) query(ies) matched no chunk (fix labels): "
                         + unlabeled.prefix(3).joined(separator: " | ")
                         + (unlabeled.count > 3 ? " …" : ""))
        }
        lines.append("")
        for q in perQuery {
            let rank = q.firstRelevantRank.map { "#\($0)" } ?? "miss"
            let r6 = q.recallAtK[6].map { pct($0) } ?? "—"
            lines.append("  [\(rank.padding(toLength: 5, withPad: " ", startingAt: 0))] r@6 \(r6)  \(q.query)")
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    private nonisolated func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}
