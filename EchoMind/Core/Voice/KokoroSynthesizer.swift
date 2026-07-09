import Foundation

// Kokoro-82M TTS (Voice Agent V4) — the warm "af_heart" voice. Guarded on a
// dedicated `FluidAudioTTS` module so that adding the FluidAudio *diarization*
// package (M3) does NOT drag in a possibly-mismatched TTS API and break the build;
// this activates only when the TTS product is explicitly linked. AVSpeechSynthesizer
// stays the floor whenever Kokoro weights aren't downloaded/linked.
//
// Add in Xcode: the FluidAudio TTS product (verify exact module name at add time —
// this space moves fast) OR an mlx-audio Kokoro package. Reconcile `synthesize`
// against the installed API — that's the single package-specific call.

#if canImport(FluidAudioTTS)
import FluidAudioTTS
import AVFoundation

@MainActor
final class KokoroSynthesizer: SpeechSynthesizing {
    private let model: LocalModel
    private var engine: KokoroTTS?
    private let player = AVAudioPlayerNode()
    private let audioEngine = AVAudioEngine()
    private var continuation: CheckedContinuation<Void, Never>?

    init(model: LocalModel) { self.model = model }

    nonisolated var isAvailable: Bool { true }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        do {
            let buffer = try await synthesize(trimmed)
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            await play(buffer)
        } catch {
            // Best-effort: a synthesis failure just produces no audio for this turn.
        }
    }

    func stop() {
        player.stop()
        resume()
    }

    // FIXME(package): reconcile with the installed Kokoro API. Expected shape:
    // load once, then render text → an AVAudioPCMBuffer of "af_heart" speech.
    private func synthesize(_ text: String) async throws -> AVAudioPCMBuffer {
        let engine = try await ensureEngine()
        return try await engine.render(text: text, voice: "af_heart")
    }

    private func ensureEngine() async throws -> KokoroTTS {
        if let engine { return engine }
        let created = try await KokoroTTS.load(repoID: model.huggingFaceRepo)
        engine = created
        return created
    }

    private func play(_ buffer: AVAudioPCMBuffer) async {
        audioEngine.attach(player)
        audioEngine.connect(player, to: audioEngine.mainMixerNode, format: buffer.format)
        try? audioEngine.start()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            player.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor in self?.resume() }
            }
            player.play()
        }
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}
#endif
