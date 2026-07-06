import Foundation
import SwiftData

/// One finalized transcription segment. `startTime`/`endTime` are offsets from
/// session start (seconds). Persisted incrementally as recording proceeds so a
/// crash loses at most the volatile tail (Phase 3).
@Model
final class TranscriptSegment {
    @Attribute(.unique) var id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var speakerLabel: String?
    var createdAt: Date
    var session: Session?

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval,
         speakerLabel: String? = nil, createdAt: Date = Date(), session: Session? = nil) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerLabel = speakerLabel
        self.createdAt = createdAt
        self.session = session
    }

    func snapshot(sessionId: UUID) -> SegmentSnapshot {
        SegmentSnapshot(id: id, sessionId: sessionId, text: text, startTime: startTime,
                        endTime: endTime, speakerLabel: speakerLabel, createdAt: createdAt)
    }
}
