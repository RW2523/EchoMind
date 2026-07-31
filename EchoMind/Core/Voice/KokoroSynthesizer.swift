import Foundation

// Kokoro TTS (Voice Agent V4) — the warm "af_heart" voice, via FluidAudio's
// KokoroAneManager (7-stage CoreML chain with ANE/GPU assignment). Compiled only
// when the FluidAudio package is linked; AVSpeechSynthesizer stays the floor
// whenever Kokoro isn't downloaded + selected, so voice output always works.
//
// The Model Manager (Settings ▸ On-Device AI ▸ Voice) prefetches the CoreML chain
// consent-gated; `initialize()` here then loads from that cache (re-downloading
// only if the OS evicted it — covered by the user's original download consent).
//
// Known OS caveat (surfaced by the package itself): iOS 26.4–26.5.x has an Apple
// BNNS bug that can intermittently crash Kokoro synthesis; fixed in 26.6.

#if canImport(FluidAudio)
import FluidAudio
import AVFoundation

@MainActor
final class KokoroSynthesizer: NSObject, SpeechSynthesizing {
    private let model: LocalModel
    private let manager = KokoroAneManager(variant: .english)
    private var initialized = false
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    init(model: LocalModel) {
        self.model = model
        super.init()
    }

    nonisolated var isAvailable: Bool { true }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()   // never overlap utterances
        do {
            if !initialized {
                try await manager.initialize()
                initialized = true
            }
            // nil voice → the English variant's default (the warm "af_heart").
            let wav = try await manager.synthesize(text: trimmed, voice: nil)
            guard !Task.isCancelled else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: wav)
            player.delegate = self
            self.player = player
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if !player.play() { resume() }
            }
        } catch {
            // Best-effort: a synthesis failure just produces no audio for this
            // sentence; the controller moves on to the next one.
        }
    }

    func stop() {
        player?.stop()
        player = nil
        resume()
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

extension KokoroSynthesizer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resume() }
    }
}
#endif
