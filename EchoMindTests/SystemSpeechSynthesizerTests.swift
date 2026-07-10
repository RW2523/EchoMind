import Testing
import AVFoundation
@testable import EchoMind

/// V2: the day-one voice floor should pick the best installed voice, not the raw
/// default. Quality tiers are device/OS-dependent, so we assert the contract that
/// holds everywhere: a usable voice is returned, and premium/enhanced is preferred
/// when the platform offers it for the language.
@MainActor
@Suite struct SystemSpeechSynthesizerTests {
    @Test func returnsAUsableVoiceForEnglish() {
        let voice = SystemSpeechSynthesizer.bestVoice(for: Locale(identifier: "en_US"))
        #expect(voice != nil)
        #expect(voice?.language.lowercased().hasPrefix("en") ?? false)
    }

    @Test func prefersHigherQualityWhenAvailable() {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("en") }
        guard english.contains(where: { $0.quality == .enhanced || $0.quality == .premium }) else {
            return   // platform has only default-quality English voices → nothing to assert
        }
        let picked = SystemSpeechSynthesizer.bestVoice(for: Locale(identifier: "en_US"))
        #expect(picked?.quality == .premium || picked?.quality == .enhanced)
    }

    @Test func nudgeAgreesWithAvailableQuality() {
        // The "install a better voice" nudge must fire iff no enhanced/premium voice
        // exists for the language — never contradict what bestVoice could pick.
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("en") }
        let hasBetter = english.contains { $0.quality == .enhanced || $0.quality == .premium }
        let nudge = SystemSpeechSynthesizer.onlyDefaultQualityAvailable(for: Locale(identifier: "en_US"))
        if !english.isEmpty { #expect(nudge == !hasBetter) }
    }
}
