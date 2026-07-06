import Foundation

/// Knowledge-chunk persistence (Phase 7). `fetchAll` feeds the brute-force
/// vector scan; `deleteAll` backs "Rebuild index" (Phase 7/9).
nonisolated protocol ChunkRepository: Sendable {
    func insert(_ chunks: [ChunkSnapshot]) async throws
    func fetchAll() async throws -> [ChunkSnapshot]
    func deleteChunks(sourceId: UUID) async throws
    func deleteChunks(sourceId: UUID, sourceType: SourceType) async throws
    func deleteAll() async throws
}
