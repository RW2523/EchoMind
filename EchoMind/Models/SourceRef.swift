import Foundation

/// A citation attached to an assistant `ChatMessage` (spec §8): points back to
/// the knowledge source (and specific chunk) an answer was grounded in.
///
/// Persisted as JSON inside `ChatMessage.sourceRefsData` (Phase 8) — never
/// queried into, so its encoding just needs to be deterministic and stable.
nonisolated struct SourceRef: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var sourceId: UUID
    var sourceType: SourceType
    var chunkId: UUID?

    init(id: UUID = UUID(), sourceId: UUID, sourceType: SourceType, chunkId: UUID? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.sourceType = sourceType
        self.chunkId = chunkId
    }
}
