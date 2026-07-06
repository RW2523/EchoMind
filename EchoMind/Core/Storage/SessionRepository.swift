import Foundation

/// Errors surfaced by the storage layer.
nonisolated enum StorageError: Error, Equatable {
    case sessionNotFound
}

/// Session persistence. Implementations are `@ModelActor` actors so writes run
/// off the main actor (Phase 3 incremental segment writes). View models depend
/// on this protocol, never on SwiftData types. `delete` cascades segments (DB
/// relationship) AND sweeps polymorphic knowledge chunks (§2.2).
nonisolated protocol SessionRepository: Sendable {
    func create(_ snapshot: SessionSnapshot) async throws
    func appendSegment(_ segment: SegmentSnapshot, toSession id: UUID) async throws
    func update(_ snapshot: SessionSnapshot) async throws
    func fetchAll() async throws -> [SessionSnapshot]
    func fetchSession(id: UUID) async throws -> SessionSnapshot?
    func fetchSegments(sessionId: UUID) async throws -> [SegmentSnapshot]
    func delete(id: UUID) async throws
}
