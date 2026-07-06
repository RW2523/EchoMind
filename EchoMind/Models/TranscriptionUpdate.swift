import Foundation

/// One transcription result. Volatile updates (`isFinal == false`) are
/// superseded by later ones; final updates carry authoritative text + range.
nonisolated struct TranscriptionUpdate: Sendable, Equatable {
    let text: String
    let isFinal: Bool
    let audioRange: ClosedRange<TimeInterval>   // seconds from session start

    init(text: String, isFinal: Bool, audioRange: ClosedRange<TimeInterval>) {
        self.text = text
        self.isFinal = isFinal
        self.audioRange = audioRange
    }
}
