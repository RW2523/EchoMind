import Foundation

/// Capture lifecycle state (drives the recording indicator and gating).
nonisolated enum RecordingState: Sendable, Equatable {
    case idle
    case recording
    case pausedByInterruption
}

/// UI-facing events published by `AudioEngineManager` (§3.2). The view model
/// renders the latest value of each; it holds no timer or level state of its own.
nonisolated enum AudioEngineEvent: Sendable, Equatable {
    case stateChanged(RecordingState)
    case level(Float)                       // 0…1, ~10 Hz
    case elapsed(TimeInterval)              // accumulated ACTIVE seconds, ~1 Hz, frozen while paused
    case inputFormatChanged(sampleRate: Double, channels: UInt32)
}
