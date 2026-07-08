import Foundation

/// Maps diarization spans onto transcript segments (M3). Diarization and the
/// transcriber cut time differently, so each transcript segment is attributed to
/// the speaker whose spans overlap it the most. Pure and deterministic — the whole
/// correctness of speaker labels rests here, so it's exhaustively unit-testable.
nonisolated enum SpeakerLabeler {
    nonisolated struct Span: Sendable, Equatable {
        let id: UUID
        let start: TimeInterval
        let end: TimeInterval
    }

    /// Returns `segmentId → speaker` only for segments with a clear overlap.
    /// Segments with no overlapping speaker are left unlabelled.
    static func assign(transcript: [Span], diarization: [SpeakerSegment]) -> [UUID: String] {
        guard !diarization.isEmpty else { return [:] }
        var result: [UUID: String] = [:]
        for segment in transcript {
            var overlapBySpeaker: [String: TimeInterval] = [:]
            for span in diarization {
                let overlap = Self.overlap(segment.start, segment.end, span.start, span.end)
                if overlap > 0 { overlapBySpeaker[span.speaker, default: 0] += overlap }
            }
            if let winner = bestSpeaker(overlapBySpeaker) {
                result[segment.id] = winner
            }
        }
        return result
    }

    /// Length of the intersection of two time intervals (0 if disjoint).
    static func overlap(_ start1: TimeInterval, _ end1: TimeInterval,
                        _ start2: TimeInterval, _ end2: TimeInterval) -> TimeInterval {
        max(0, min(end1, end2) - max(start1, start2))
    }

    /// Greatest total overlap wins; ties break to the lexicographically smaller
    /// speaker so the result is independent of dictionary iteration order.
    private static func bestSpeaker(_ overlaps: [String: TimeInterval]) -> String? {
        var best: String?
        var bestOverlap: TimeInterval = 0
        for (speaker, total) in overlaps {
            if best == nil || total > bestOverlap || (total == bestOverlap && speaker < best!) {
                best = speaker
                bestOverlap = total
            }
        }
        return best
    }
}
