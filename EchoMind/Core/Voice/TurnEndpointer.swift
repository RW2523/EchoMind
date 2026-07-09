import Foundation

/// Decides when the user has finished speaking (Voice Agent V3, hands-free). Pure
/// logic fed the live partial transcript + a timestamp: once speech has been seen
/// and the transcript then stays unchanged for `holdInterval`, the turn ends. This
/// is the first-party endpointing floor (works off the transcript we already
/// stream); `SpeechDetector` VAD can drive the same decision on device.
nonisolated struct TurnEndpointer {
    let holdInterval: TimeInterval

    private var lastChange: TimeInterval?
    private var lastTranscript = ""
    private var heardSpeech = false

    init(holdInterval: TimeInterval = 0.8) { self.holdInterval = holdInterval }

    /// Feed the newest partial transcript with the current time (seconds).
    mutating func update(transcript: String, now: TimeInterval) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastTranscript else { return }
        lastTranscript = trimmed
        lastChange = now
        if !trimmed.isEmpty { heardSpeech = true }
    }

    /// True once we've heard speech and then had `holdInterval` of quiet.
    func shouldEndTurn(now: TimeInterval) -> Bool {
        guard heardSpeech, !lastTranscript.isEmpty, let lastChange else { return false }
        return now - lastChange >= holdInterval - 1e-6   // epsilon: FP-safe at the boundary
    }

    /// Whether any speech has been captured this turn (for barge-in detection).
    var hasSpeech: Bool { heardSpeech && !lastTranscript.isEmpty }

    var transcript: String { lastTranscript }

    mutating func reset() {
        lastChange = nil
        lastTranscript = ""
        heardSpeech = false
    }
}
