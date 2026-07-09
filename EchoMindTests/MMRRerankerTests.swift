import Testing
import Foundation
@testable import EchoMind

@Suite struct MMRRerankerTests {
    private func normalize(_ v: [Float]) -> [Float] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return mag == 0 ? v : v.map { $0 / mag }
    }

    // q≈x-axis. A is most relevant; B is a near-duplicate of A; C is less relevant
    // but diverse. Plain relevance ranks A,B,C — so top-2 = [A,B] (redundant).
    private let q: [Float] = [1, 0, 0]
    private let idA = UUID()
    private let idB = UUID()
    private let idC = UUID()
    private var candidates: [(id: UUID, vector: [Float])] {
        [
            (idA, normalize([4, 1, 0])),
            (idB, normalize([4, 1.1, 0])),   // ~duplicate of A
            (idC, normalize([2, 0, 2])),     // diverse
        ]
    }

    @Test func diversityLambdaPrefersDiverseOverDuplicate() {
        let picked = MMRReranker(lambda: 0.5).rerank(query: q, candidates: candidates, k: 2)
        #expect(picked.first == idA)      // most relevant still leads
        #expect(picked == [idA, idC])     // diverse C beats near-duplicate B
    }

    @Test func lambdaOneReducesToPureRelevance() {
        let picked = MMRReranker(lambda: 1.0).rerank(query: q, candidates: candidates, k: 2)
        #expect(picked == [idA, idB])     // no diversity term → relevance order
    }

    @Test func firstPickIsMostRelevant() {
        let picked = MMRReranker(lambda: 0.7).rerank(query: q, candidates: candidates, k: 3)
        #expect(picked.first == idA)
        #expect(picked.count == 3)
    }

    @Test func handlesEdgeCases() {
        let r = MMRReranker()
        #expect(r.rerank(query: q, candidates: [], k: 3).isEmpty)
        #expect(r.rerank(query: q, candidates: [(UUID(), [1, 0, 0])], k: 0).isEmpty)
        #expect(r.rerank(query: [], candidates: [(UUID(), [1, 0, 0])], k: 3).isEmpty)
    }

    @Test func dropsDimensionMismatchedVectors() {
        let good = UUID()
        let picked = MMRReranker().rerank(
            query: q,
            candidates: [(good, [1, 0, 0]), (UUID(), [1, 0])],   // second is wrong dim
            k: 5)
        #expect(picked == [good])
    }
}
