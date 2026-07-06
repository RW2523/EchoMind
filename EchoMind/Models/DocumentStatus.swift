import Foundation

/// Indexing lifecycle of an imported `Document` (spec §8).
/// `.imported` on import (Phase 6) → `.indexing` → `.ready` once chunks +
/// embeddings are stored (Phase 7); `.failed` on extraction/indexing error.
nonisolated enum DocumentStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case imported
    case indexing
    case ready
    case failed
}

/// Supported import file types (Phase 6). Stored as `Document.fileTypeRaw`.
nonisolated enum DocumentFileType: String, Codable, Sendable, CaseIterable, Hashable {
    case txt
    case md
    case pdf
}
