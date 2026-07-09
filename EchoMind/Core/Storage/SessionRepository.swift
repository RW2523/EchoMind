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

    // Phase 4 additions
    func recentSessions(limit: Int?) async throws -> [SessionSnapshot]
    func search(matching query: String) async throws -> [SessionSnapshot]
    func previewText(sessionID: UUID, maxCharacters: Int) async throws -> String
    func rename(sessionID: UUID, to title: String) async throws

    // M3: persist diarization results (segmentId → speaker label).
    func setSpeakerLabels(_ labels: [UUID: String], sessionId: UUID) async throws

    // R1: auto-report — these touch only the report columns (never clobber the rest).
    func setReportState(_ state: ReportState, sessionId: UUID) async throws
    func setReport(summaryJSON: String, sessionId: UUID) async throws
    func setActionStates(_ statesJSON: String, sessionId: UUID) async throws
}
