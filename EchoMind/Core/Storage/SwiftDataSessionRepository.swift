import Foundation
import SwiftData

@ModelActor
actor SwiftDataSessionRepository: SessionRepository {
    func create(_ snapshot: SessionSnapshot) async throws {
        let session = Session(id: snapshot.id, title: snapshot.title, createdAt: snapshot.createdAt,
                              updatedAt: snapshot.updatedAt, duration: snapshot.duration,
                              summaryJSON: snapshot.summaryJSON, origin: snapshot.origin,
                              tags: snapshot.tags)
        modelContext.insert(session)
        try modelContext.save()
    }

    func appendSegment(_ segment: SegmentSnapshot, toSession id: UUID) async throws {
        guard let session = try sessionModel(id: id) else { throw StorageError.sessionNotFound }
        let model = TranscriptSegment(id: segment.id, text: segment.text, startTime: segment.startTime,
                                      endTime: segment.endTime, speakerLabel: segment.speakerLabel,
                                      createdAt: segment.createdAt, session: session)
        modelContext.insert(model)
        try modelContext.save()
    }

    func update(_ snapshot: SessionSnapshot) async throws {
        guard let session = try sessionModel(id: snapshot.id) else { throw StorageError.sessionNotFound }
        session.title = snapshot.title
        session.updatedAt = snapshot.updatedAt
        session.duration = snapshot.duration
        session.summaryJSON = snapshot.summaryJSON
        session.origin = snapshot.origin
        session.tags = snapshot.tags
        try modelContext.save()
    }

    func fetchAll() async throws -> [SessionSnapshot] {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func fetchSession(id: UUID) async throws -> SessionSnapshot? {
        try sessionModel(id: id)?.snapshot
    }

    func fetchSegments(sessionId: UUID) async throws -> [SegmentSnapshot] {
        guard let session = try sessionModel(id: sessionId) else { return [] }
        return session.segments
            .sorted { $0.startTime < $1.startTime }
            .map { $0.snapshot(sessionId: sessionId) }
    }

    func delete(id: UUID) async throws {
        guard let session = try sessionModel(id: id) else { return }
        modelContext.delete(session)          // cascades TranscriptSegments (DB relationship)
        try sweepChunks(sourceId: id)         // polymorphic chunks have no relationship
        try modelContext.save()               // one transaction
    }

    // MARK: - Phase 4

    func recentSessions(limit: Int?) async throws -> [SessionSnapshot] {
        var descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func search(matching query: String) async throws -> [SessionSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try await fetchAll() }
        let sessions = try modelContext.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        return sessions.filter { session in
            session.title.localizedStandardContains(trimmed)
                || session.segments.contains { $0.text.localizedStandardContains(trimmed) }
        }.map(\.snapshot)
    }

    func previewText(sessionID: UUID, maxCharacters: Int) async throws -> String {
        guard let session = try sessionModel(id: sessionID) else { return "" }
        let joined = session.segments
            .sorted { $0.startTime < $1.startTime }
            .map(\.text)
            .joined(separator: " ")
        let collapsed = joined.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(maxCharacters))
    }

    func rename(sessionID: UUID, to title: String) async throws {
        guard let session = try sessionModel(id: sessionID) else { throw StorageError.sessionNotFound }
        session.title = title
        session.updatedAt = Date()
        try modelContext.save()
    }

    func setSpeakerLabels(_ labels: [UUID: String], sessionId: UUID) async throws {
        guard let session = try sessionModel(id: sessionId) else { throw StorageError.sessionNotFound }
        for segment in session.segments {
            if let label = labels[segment.id] { segment.speakerLabel = label }
        }
        try modelContext.save()
    }

    // MARK: - Helpers

    private func sessionModel(id: UUID) throws -> Session? {
        var descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func sweepChunks(sourceId: UUID) throws {
        let descriptor = FetchDescriptor<KnowledgeChunk>(predicate: #Predicate { $0.sourceId == sourceId })
        for chunk in try modelContext.fetch(descriptor) { modelContext.delete(chunk) }
    }
}
