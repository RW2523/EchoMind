import AVFoundation

/// Transfers an `AVAudioPCMBuffer` across concurrency domains (audio tap →
/// transcriber). `@unchecked Sendable` is justified: each tapped buffer is
/// produced fresh by Core Audio and handed off exactly once, never mutated or
/// read again on the audio thread after being yielded.
nonisolated struct AudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
