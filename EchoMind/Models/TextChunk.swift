import Foundation

/// Pre-persistence chunk (text + metadata) produced by the chunker (§6.2).
nonisolated struct TextChunk: Sendable, Equatable {
    let text: String
    let sourceId: UUID
    let sourceType: SourceType
    let chunkIndex: Int
    let pageNumber: Int?        // documents only
    let timestamp: TimeInterval?   // sessions only — startTime of first contributing segment
}

/// A stored chunk plus its retrieval score (Phase 8).
nonisolated struct RetrievedChunk: Sendable, Equatable {
    let chunk: ChunkSnapshot
    let score: Float
}
