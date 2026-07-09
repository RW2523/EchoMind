import Foundation
import AVFoundation

/// Playback for a retained session recording (P17). Observable so the player bar
/// and scrubber update live; drives tap-to-play by seeking to a segment's start
/// time. One player at a time, scoped to the open session detail.
@MainActor
@Observable
final class AudioPlaybackService {
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isLoaded = false

    /// Loads a file for playback. Returns false if it can't be opened.
    @discardableResult
    func load(url: URL) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        isLoaded = true
        return true
    }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, duration))
        currentTime = player.currentTime
    }

    /// Tap-to-play: jump to a transcript segment and start playing.
    func playFrom(_ time: TimeInterval) {
        seek(to: time)
        play()
    }

    func stop() {
        pause()
        player?.currentTime = 0
        currentTime = 0
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { break }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    // No deinit needed: the ticker captures [weak self] and exits once this
    // object deallocates (guard let self fails), so it can't outlive the player.
}
