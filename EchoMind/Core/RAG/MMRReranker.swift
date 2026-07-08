import Foundation
import Accelerate

/// Maximal Marginal Relevance reranking (V2 §A6, Phase 16). Reorders a
/// relevance-ranked candidate pool to cut redundancy: each successive pick
/// maximises
///     λ · sim(query, d) − (1 − λ) · max sim(d, alreadyPicked)
/// so the context handed to the model covers distinct facts instead of three
/// paraphrases of the same sentence. Pure vDSP over the embeddings we already
/// store — no model, no download. Vectors are assumed L2-normalized (our
/// embedder guarantees it), so a dot product IS cosine similarity.
nonisolated struct MMRReranker: Sendable {
    /// 1.0 = pure relevance (no diversity); lower trades relevance for coverage.
    let lambda: Float

    init(lambda: Float = 0.7) { self.lambda = lambda }

    /// Returns up to `k` ids, greedily MMR-ordered. Candidates whose vector
    /// dimension doesn't match the query are dropped.
    func rerank(query: [Float], candidates: [(id: UUID, vector: [Float])], k: Int) -> [UUID] {
        guard k > 0, !query.isEmpty else { return [] }
        let dim = query.count
        var remaining = candidates.filter { $0.vector.count == dim }
        guard !remaining.isEmpty else { return [] }

        let relevance = Dictionary(uniqueKeysWithValues:
            remaining.map { ($0.id, dot($0.vector, query)) })

        var selected: [(id: UUID, vector: [Float])] = []
        let target = min(k, remaining.count)
        while selected.count < target, !remaining.isEmpty {
            var bestIndex = 0
            var bestScore = -Float.greatestFiniteMagnitude
            for (i, candidate) in remaining.enumerated() {
                let rel = relevance[candidate.id] ?? 0
                var maxSim: Float = 0
                for chosen in selected {
                    maxSim = max(maxSim, dot(candidate.vector, chosen.vector))
                }
                let score = lambda * rel - (1 - lambda) * maxSim
                if score > bestScore {
                    bestScore = score
                    bestIndex = i
                }
            }
            selected.append(remaining.remove(at: bestIndex))
        }
        return selected.map(\.id)
    }

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }
}
