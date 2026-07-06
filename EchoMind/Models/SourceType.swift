import Foundation

/// The kind of knowledge source a chunk or citation refers to.
///
/// Shared across `KnowledgeChunk`, `SourceRef`, `ChunkSnapshot`, and the
/// repositories' chunk-sweep logic (spec §8). There is exactly ONE `SourceType`
/// in the app — do not introduce a parallel enum for the same concept.
///
/// `nonisolated` because these value types cross actor boundaries (built by the
/// `@ModelActor` repositories off the main actor); the project defaults to
/// MainActor isolation, which we opt out of for the storage/domain layer.
nonisolated enum SourceType: String, Codable, Sendable, CaseIterable, Hashable {
    case document
    case session
}

/// How a `Session` originated. Distinct concept from `SourceType`: this records
/// whether a session came from live recording or an imported source. Spec §8
/// calls this Session.sourceType (live/import); named `SessionOrigin` here to
/// avoid colliding with the knowledge-source `SourceType` above.
nonisolated enum SessionOrigin: String, Codable, Sendable, CaseIterable, Hashable {
    case live
    case imported
}
