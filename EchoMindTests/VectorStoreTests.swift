import Testing
import Foundation
@testable import EchoMind

@Suite struct VectorStoreTests {
    private func normalize(_ v: [Float]) -> [Float] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return mag == 0 ? v : v.map { $0 / mag }
    }

    @Test func searchReturnsNearestFirst() async throws {
        let store = InMemoryVectorStore()
        let a = UUID(), b = UUID(), c = UUID()
        try await store.upsert([
            (a, normalize([1, 0, 0])),
            (b, normalize([0.9, 0.1, 0])),
            (c, normalize([0, 1, 0])),
        ])
        let results = try await store.search(query: normalize([1, 0, 0]), k: 3)
        #expect(results.first?.id == a)
        #expect(results.last?.id == c)   // orthogonal → least similar
    }

    @Test func matchesVectorSearchDirectly() async throws {
        let store = InMemoryVectorStore()
        let ids = (0..<5).map { _ in UUID() }
        let vectors = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0.7, 0.7, 0], [0.5, 0.5, 0.7]]
            .map { normalize($0.map(Float.init)) }
        try await store.upsert(Array(zip(ids, vectors)).map { (id: $0.0, vector: $0.1) })

        let query = normalize([0.9, 0.2, 0])
        let storeResult = try await store.search(query: query, k: 3).map(\.id)
        let direct = VectorSearch().topK(
            query: query,
            candidates: Array(zip(ids, vectors)).map { (id: $0.0, vector: $0.1) },
            k: 3).map(\.id)
        #expect(storeResult == direct)
    }

    @Test func upsertReplacesAndCountTracks() async throws {
        let store = InMemoryVectorStore()
        let id = UUID()
        try await store.upsert([(id, normalize([1, 0]))])
        #expect(try await store.count() == 1)
        try await store.upsert([(id, normalize([0, 1]))])   // replace, not add
        #expect(try await store.count() == 1)
    }

    @Test func removeAndRemoveAll() async throws {
        let store = InMemoryVectorStore()
        let a = UUID(), b = UUID()
        try await store.upsert([(a, normalize([1, 0])), (b, normalize([0, 1]))])
        try await store.remove(ids: [a])
        #expect(try await store.count() == 1)
        try await store.removeAll()
        #expect(try await store.count() == 0)
    }

    @Test func searchOnEmptyStoreReturnsNothing() async throws {
        let store = InMemoryVectorStore()
        #expect(try await store.search(query: normalize([1, 0]), k: 5).isEmpty)
    }
}
