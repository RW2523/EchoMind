import Foundation

/// Decides when a *new* spoken utterance has begun, from the growing partial
/// transcript of a mic that's kept open while the agent is speaking (hands-free
/// barge-in, V3). The transcript comes from a fresh capture that starts empty, so
/// any content is user speech — but echo cancellation isn't perfect and a stray
/// syllable of the agent's own TTS can leak through, so onset requires a minimum of
/// real words before we cut the agent off. Pure and deterministic → unit-testable.
nonisolated struct SpeechOnsetDetector {
    let minWords: Int
    let minCharacters: Int

    init(minWords: Int = 2, minCharacters: Int = 5) {
        self.minWords = minWords
        self.minCharacters = minCharacters
    }

    func detectedOnset(in transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minCharacters else { return false }
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" })
        return words.count >= minWords
    }
}
