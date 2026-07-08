import Foundation

/// A persistent-capable vector index seam (M4). The default `InMemoryVectorStore`
/// is exactly today's brute-force vDSP search (sub-ms at personal scale); a
/// `SQLiteVecVectorStore` drops in behind `#if canImport(SQLiteVec)` only when the
/// corpus is large enough to warrant an on-disk index. RAG keeps talking to this
/// protocol, so the swap is invisible upstream.
nonisolated protocol VectorStore: Sendable {
    func upsert(_ entries: [(id: UUID, vector: [Float])]) async throws
    func remove(ids: [UUID]) async throws
    func removeAll() async throws
    func search(query: [Float], k: Int) async throws -> [(id: UUID, score: Float)]
    func count() async throws -> Int
}

/// Brute-force, in-memory implementation — identical results to `VectorSearch`
/// (which it uses), fully testable, no package. This is the shipping default; the
/// deferral note in MODEL_STACK_PLAN.md explains why on-disk indexing waits.
actor InMemoryVectorStore: VectorStore {
    private var vectors: [UUID: [Float]] = [:]
    private let searcher = VectorSearch()

    init() {}

    func upsert(_ entries: [(id: UUID, vector: [Float])]) {
        for entry in entries { vectors[entry.id] = entry.vector }
    }

    func remove(ids: [UUID]) {
        for id in ids { vectors[id] = nil }
    }

    func removeAll() { vectors.removeAll() }

    func count() -> Int { vectors.count }

    func search(query: [Float], k: Int) -> [(id: UUID, score: Float)] {
        searcher.topK(query: query,
                      candidates: vectors.map { (id: $0.key, vector: $0.value) },
                      k: k)
    }
}
