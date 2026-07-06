import Foundation
import Accelerate

/// Brute-force cosine via vDSP dot product on PRE-NORMALIZED vectors (so
/// dot == cosine). Brute force is the design — no index structures (§6.3).
nonisolated struct VectorSearch: Sendable {
    func topK(query: [Float],
              candidates: [(id: UUID, vector: [Float])],
              k: Int) -> [(id: UUID, score: Float)] {
        guard !query.isEmpty, k > 0 else { return [] }
        let dimension = query.count
        var scored: [(id: UUID, score: Float)] = []
        scored.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard candidate.vector.count == dimension else { continue }
            var dot: Float = 0
            vDSP_dotpr(query, 1, candidate.vector, 1, &dot, vDSP_Length(dimension))
            scored.append((candidate.id, dot))
        }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(k))
    }
}
