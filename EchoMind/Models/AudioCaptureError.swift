import Foundation

/// Typed errors for the audio capture path.
nonisolated enum AudioCaptureError: Error, Equatable {
    case alreadyCapturing
    case sessionConfigurationFailed(String)
    case engineStartFailed(String)
    case tapInstallFailed
}
