import Foundation
import AVFoundation

/// Wraps `AVAudioSession` category/activation in one place (§3.2). The single
/// file to adjust if AirPods input or route handling misbehaves on device.
nonisolated protocol AudioSessionConfiguring: Sendable {
    func activate() throws
    func deactivate() throws
}

nonisolated struct AudioSessionConfigurator: AudioSessionConfiguring {
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord tolerates route changes better than .record; HFP is
        // required for AirPods mic input; avoid .measurement (kills input
        // processing that helps speech).
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.allowBluetoothHFP, .duckOthers])
        try session.setActive(true)
    }

    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
