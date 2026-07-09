import Foundation

// The ONLY file that touches the sqlite-vec package. Compiled solely when linked
// (`#if canImport(SQLiteVec)`); otherwise `InMemoryVectorStore` is used. On-disk,
// indexed vector search for large corpora — see the M4 trigger in
// MODEL_STACK_PLAN.md. The table/query calls are the reconciliation point if the
// SQLiteVec API drifted; everything upstream speaks the `VectorStore` protocol.
//
// Add in Xcode: File ▸ Add Package Dependencies… ▸
//   https://github.com/asg017/sqlite-vec   (product: SQLiteVec)

#if canImport(SQLiteVec)
import SQLiteVec

actor SQLiteVecVectorStore: VectorStore {
    private let url: URL
    private var db: Database?
    private var dimension: Int?

    init(url: URL) { self.url = url }

    private func database(dimension dim: Int) async throws -> Database {
        if let db { return db }
        try SQLiteVec.initialize()
        let database = try Database(.uri(url.path))
        // vec0 virtual table keyed by the chunk id; float[dim] embedding column.
        try await database.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(id TEXT PRIMARY KEY, embedding float[\(dim)])")
        db = database
        dimension = dim
        return database
    }

    func upsert(_ entries: [(id: UUID, vector: [Float])]) async throws {
        guard let first = entries.first else { return }
        let database = try await database(dimension: first.vector.count)
        for entry in entries {
            try await database.execute(
                "INSERT OR REPLACE INTO vec_chunks(id, embedding) VALUES (?, ?)",
                params: [entry.id.uuidString, entry.vector])
        }
    }

    func remove(ids: [UUID]) async throws {
        guard let db else { return }
        for id in ids {
            try await db.execute("DELETE FROM vec_chunks WHERE id = ?", params: [id.uuidString])
        }
    }

    func removeAll() async throws {
        try? await db?.execute("DELETE FROM vec_chunks")
    }

    func count() async throws -> Int {
        guard let db else { return 0 }
        let rows = try await db.query("SELECT COUNT(*) AS c FROM vec_chunks")
        return (rows.first?["c"] as? Int) ?? 0
    }

    func search(query: [Float], k: Int) async throws -> [(id: UUID, score: Float)] {
        let database = try await database(dimension: query.count)
        // Vectors are L2-normalized, so ascending L2 distance == descending cosine.
        // Return score = -distance so "higher is better" matches VectorStore's contract.
        let rows = try await database.query(
            "SELECT id, distance FROM vec_chunks WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
            params: [query, k])
        return rows.compactMap { row in
            guard let idString = row["id"] as? String, let id = UUID(uuidString: idString) else { return nil }
            let distance = (row["distance"] as? Double).map(Float.init) ?? 0
            return (id: id, score: -distance)
        }
    }
}
#endif
