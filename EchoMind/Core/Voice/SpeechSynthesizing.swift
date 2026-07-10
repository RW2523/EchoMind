import Foundation
import AVFoundation

/// Text-to-speech seam (Voice Agent V1). `SystemSpeechSynthesizer` is the
/// first-party floor (AVSpeechSynthesizer — on-device, no download, ships day one);
/// a Kokoro-backed synthesizer drops in behind `#if canImport` later (V4) without
/// touching the controller. `@MainActor` because the controller and AVSpeech both
/// live there and speak/stop are UI-driven.
@MainActor
protocol SpeechSynthesizing {
    var isAvailable: Bool { get }
    /// Speaks `text`, returning when the utterance finishes OR is stopped.
    func speak(_ text: String) async
    func stop()
}

/// AVSpeechSynthesizer implementation. Bridges the delegate's finish/cancel
/// callbacks into async completion so the controller can `await` an utterance.
/// Picks the best-sounding installed voice (premium ▸ enhanced ▸ default) so the
/// day-one floor sounds as natural as the OS allows — no download, no package.
@MainActor
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private let voice: AVSpeechSynthesisVoice?

    nonisolated var isAvailable: Bool { true }

    init(locale: Locale = .current) {
        self.voice = Self.bestVoice(for: locale)
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()   // never overlap utterances
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: trimmed)
        if let voice { utterance.voice = voice }
        // A hair slower than the raw default reads as conversational, not clipped.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.05
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    /// Highest-quality installed voice for the locale's language: premium if the
    /// user downloaded one (Settings ▸ Accessibility ▸ Spoken Content), else
    /// enhanced, else whatever the language default is. Nil → OS default voice.
    static func bestVoice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String((locale.language.languageCode?.identifier ?? lang).prefix(2)).lowercased()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix(prefix)
        }
        func pick(_ q: AVSpeechSynthesisVoiceQuality) -> AVSpeechSynthesisVoice? {
            voices.first { $0.quality == q }
        }
        return pick(.premium) ?? pick(.enhanced) ?? voices.first
            ?? AVSpeechSynthesisVoice(language: lang)
    }

    /// True when the device has only default-quality voices installed for the
    /// language — the cue to nudge the user to install an enhanced/premium one.
    /// Returns false when we can't tell (no matching voices) so we never nag wrongly.
    static func onlyDefaultQualityAvailable(for locale: Locale = .current) -> Bool {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String((locale.language.languageCode?.identifier ?? lang).prefix(2)).lowercased()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix(prefix)
        }
        guard !voices.isEmpty else { return false }
        return !voices.contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resume()
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

extension SystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}
