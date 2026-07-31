import Foundation

/// The decoded retrieval corpus, cached between questions (RAG 2.0).
///
/// Before this cache, EVERY question re-fetched every chunk row and re-unpacked
/// every embedding blob — the phone-scale bottleneck (O(corpus) SwiftData I/O +
/// Float decoding per keystroke of curiosity). Now the corpus is decoded once and
/// served from memory; a cheap row-count staleness probe catches deletions, and
/// the indexer/wipe hooks invalidate explicitly on writes. Memory cost is modest:
/// text + one [Float] per chunk (~3 KB each → a few MB for thousands of chunks).
actor CorpusCache {
    /// One retrievable unit, decoded and ready for vDSP.
    nonisolated struct Entry: Sendable {
        let id: UUID
        let sourceId: UUID
        let sourceType: SourceType
        let text: String
        /// nil when the stored blob didn't match the embedder dimension.
        let vector: [Float]?
        let createdAt: Date
    }

    private let chunks: any ChunkRepository
    private let dimension: @Sendable () async throws -> Int
    private var cached: [Entry]?
    private var cachedCount = -1

    init(chunks: any ChunkRepository, dimension: @escaping @Sendable () async throws -> Int) {
        self.chunks = chunks
        self.dimension = dimension
    }

    /// The corpus, decoding it only when absent or stale (row count changed —
    /// catches deletes that don't flow through the indexer hooks).
    func corpus() async throws -> [Entry] {
        if let cached, (try? await chunks.count()) == cachedCount {
            return cached
        }
        let dim = try await dimension()
        let stored = try await chunks.fetchAll()
        let entries = stored.map { chunk in
            Entry(id: chunk.id,
                  sourceId: chunk.sourceId,
                  sourceType: chunk.sourceType,
                  text: chunk.text,
                  vector: try? VectorPacking.unpack(chunk.embedding, expectedDimension: dim),
                  createdAt: chunk.createdAt)
        }
        cached = entries
        cachedCount = stored.count
        return entries
    }

    /// Drop the cache — called after indexing, rebuilds, and Delete All Data.
    func invalidate() {
        cached = nil
        cachedCount = -1
    }
}
