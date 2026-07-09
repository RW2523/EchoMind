import Testing
@testable import EchoMind

/// Bug 6: hands-free barge-in needs to tell a real spoken interruption from a stray
/// syllable of TTS leaking past echo cancellation. These pin that threshold.
@Suite struct SpeechOnsetDetectorTests {
    let detector = SpeechOnsetDetector()

    @Test func detectsARealUtterance() {
        #expect(detector.detectedOnset(in: "wait stop"))
        #expect(detector.detectedOnset(in: "actually what about pricing"))
    }

    @Test func ignoresEmptyOrTrivialLeakage() {
        #expect(!detector.detectedOnset(in: ""))
        #expect(!detector.detectedOnset(in: "   "))
        #expect(!detector.detectedOnset(in: "uh"))      // one short token
        #expect(!detector.detectedOnset(in: "a"))
    }

    @Test func requiresMinimumWordsAndLength() {
        // Two words but too few characters overall stays below the bar.
        #expect(!detector.detectedOnset(in: "a b"))
        // Meets both word and character minimums.
        #expect(detector.detectedOnset(in: "no wait"))
    }

    @Test func customThresholdIsHonored() {
        let strict = SpeechOnsetDetector(minWords: 3, minCharacters: 8)
        #expect(!strict.detectedOnset(in: "no wait"))
        #expect(strict.detectedOnset(in: "no wait stop"))
    }
}
