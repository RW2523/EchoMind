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
@MainActor
final class SystemSpeechSynthesizer: NSObject, SpeechSynthesizing {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    nonisolated var isAvailable: Bool { true }

    override init() {
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
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
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
