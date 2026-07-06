import Foundation
import AVFoundation
import Accelerate

/// Computes a normalized 0…1 level from a PCM buffer's RMS (in dBFS). Called
/// from the audio-thread tap block, so it allocates nothing.
nonisolated struct AudioLevelMeter {
    private let floorDb: Float = -60

    func level(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frames))
        let db = 20 * log10(max(rms, 1e-7))
        let clamped = max(floorDb, min(0, db))
        return (clamped - floorDb) / -floorDb
    }
}
