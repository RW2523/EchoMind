import Foundation
import SwiftData

/// A ~200-word retrievable chunk with its embedding (Phase 7). `sourceId` is
/// polymorphic (a `Session.id` OR a `Document.id`); `sourceType` disambiguates.
/// Because the source is polymorphic, no SwiftData relationship is possible, so
/// deletion cascade is enforced in the repositories, not the DB (§2.2).
@Model
final class KnowledgeChunk {
    #Index<KnowledgeChunk>([\.sourceId])
    @Attribute(.unique) var id: UUID
    var sourceId: UUID
    var sourceTypeRaw: String
    var text: String
    /// Packed little-endian [Float], stored inline (NOT .externalStorage) so
    /// brute-force search bulk-loads thousands of vectors via row fetches, not
    /// file opens. Pack/unpack utilities land in Phase 7.
    var embedding: Data
    var chunkIndex: Int
    var pageNumber: Int?
    var timestamp: TimeInterval?
    var createdAt: Date

    var sourceType: SourceType {
        get { SourceType(rawValue: sourceTypeRaw) ?? .document }
        set { sourceTypeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), sourceId: UUID, sourceType: SourceType, text: String,
         embedding: Data = Data(), chunkIndex: Int, pageNumber: Int? = nil,
         timestamp: TimeInterval? = nil, createdAt: Date = Date()) {
        self.id = id
        self.sourceId = sourceId
        self.sourceTypeRaw = sourceType.rawValue
        self.text = text
        self.embedding = embedding
        self.chunkIndex = chunkIndex
        self.pageNumber = pageNumber
        self.timestamp = timestamp
        self.createdAt = createdAt
    }

    var snapshot: ChunkSnapshot {
        ChunkSnapshot(id: id, sourceId: sourceId, sourceType: sourceType, text: text,
                      embedding: embedding, chunkIndex: chunkIndex, pageNumber: pageNumber,
                      timestamp: timestamp, createdAt: createdAt)
    }
}
