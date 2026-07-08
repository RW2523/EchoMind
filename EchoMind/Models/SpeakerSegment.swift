import Foundation

/// One contiguous stretch attributed to a single speaker (M3). Times are seconds
/// from the start of the recording, matching transcript segment timings.
nonisolated struct SpeakerSegment: Sendable, Equatable {
    let speaker: String        // "Speaker 1", "Speaker 2", …
    let start: TimeInterval
    let end: TimeInterval
}

nonisolated struct DiarizationResult: Sendable, Equatable {
    let segments: [SpeakerSegment]

    var speakerCount: Int { Set(segments.map(\.speaker)).count }
    var isEmpty: Bool { segments.isEmpty }

    static let empty = DiarizationResult(segments: [])
}
