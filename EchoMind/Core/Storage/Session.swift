import Foundation
import SwiftData

/// A recorded (or imported) meeting. The full transcript is DERIVED from
/// `segments` and never stored twice (§2.2) — Phase 3 persists segments
/// incrementally, so a duplicate transcript column would drift or thrash.
@Model
final class Session {
    #Index<Session>([\.createdAt])
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    /// JSON-encoded MeetingSummary, written in Phase 5. nil until summarized.
    var summaryJSON: String?
    /// SessionOrigin raw value (spec §8 Session.sourceType: live | import).
    var originRaw: String
    var tags: [String]
    /// R1: auto-report lifecycle (ReportState raw). Additive default → lightweight migration.
    var reportStateRaw: String = ReportState.none.rawValue
    /// R1: JSON `[Bool]` of action-item completion, indexed by position. nil = none checked.
    var actionStatesJSON: String?

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.session)
    var segments: [TranscriptSegment] = []

    var origin: SessionOrigin {
        get { SessionOrigin(rawValue: originRaw) ?? .live }
        set { originRaw = newValue.rawValue }
    }

    var reportState: ReportState {
        get { ReportState(rawValue: reportStateRaw) ?? .none }
        set { reportStateRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), updatedAt: Date = Date(),
         duration: TimeInterval = 0, summaryJSON: String? = nil, origin: SessionOrigin = .live,
         tags: [String] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.summaryJSON = summaryJSON
        self.originRaw = origin.rawValue
        self.tags = tags
    }

    /// Snapshot of scalar fields only (segments fetched separately by the repo).
    var snapshot: SessionSnapshot {
        SessionSnapshot(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt,
                        duration: duration, summaryJSON: summaryJSON, origin: origin, tags: tags,
                        reportState: reportState, actionStatesJSON: actionStatesJSON)
    }
}
