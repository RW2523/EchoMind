import Foundation

/// User-surfaceable transcription failures (§3.6). Every case maps to a
/// recoverable-in-place UI state, never a crash.
nonisolated enum TranscriptionError: Error, Equatable {
    case microphoneDenied
    case speechDenied
    case localeUnsupported(String)
    case assetDownloadFailed(String)
    case transcriberFailed(String)
    case sessionActivationFailed
    case insufficientStorage
}
