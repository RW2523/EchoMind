import Testing
import Foundation
@testable import EchoMind

@Suite struct VectorSearchTests {
    private let search = VectorSearch()

    private func normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return norm == 0 ? v : v.map { $0 / norm }
    }

    @Test func dotOfNormalizedVectorsEqualsCosine() {
        // Two 3-dim vectors; cosine = dot of normalized. Hand-computed.
        let a = normalize([1, 2, 3])
        let b = normalize([2, 4, 6])   // parallel -> cosine 1.0
        let id = UUID()
        let result = search.topK(query: a, candidates: [(id, b)], k: 1)
        #expect(abs(result[0].score - 1.0) < 1e-6)
    }

    @Test func orthogonalVectorsScoreZero() {
        let a = normalize([1, 0])
        let b = normalize([0, 1])
        let result = search.topK(query: a, candidates: [(UUID(), b)], k: 1)
        #expect(abs(result[0].score) < 1e-6)
    }

    @Test func topKReturnsCorrectOrdering() {
        let query = normalize([1, 0, 0])
        let candidates: [(id: UUID, vector: [Float])] = [
            (UUID(), normalize([0, 1, 0])),   // score 0
            (UUID(), normalize([1, 1, 0])),   // score ~0.707
            (UUID(), normalize([1, 0, 0])),   // score 1
        ]
        let result = search.topK(query: query, candidates: candidates, k: 2)
        #expect(result.count == 2)
        #expect(result[0].score > result[1].score)
        #expect(abs(result[0].score - 1.0) < 1e-6)
    }

    @Test func kLargerThanCandidatesReturnsAll() {
        let query = normalize([1, 0])
        let candidates = [(UUID(), normalize([1, 0])), (UUID(), normalize([0, 1]))]
        #expect(search.topK(query: query, candidates: candidates, k: 10).count == 2)
    }

    @Test func mismatchedDimensionsSkipped() {
        let query: [Float] = normalize([1, 0, 0])
        let result = search.topK(query: query, candidates: [(UUID(), [1, 0])], k: 5)
        #expect(result.isEmpty)
    }
}
