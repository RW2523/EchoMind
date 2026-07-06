import Foundation
import AVFoundation

/// Session-level events, normalized from `AVAudioSession` notifications so the
/// state machine is pure and unit-testable without hardware (§3.2).
nonisolated enum AudioSessionEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: AVAudioSession.RouteChangeReason)
    case mediaServicesReset
}

/// Commands the manager executes against the engine/session.
nonisolated enum AudioCommand: Sendable, Equatable {
    case pauseCapture
    case resumeCapture
    case reinstallTap
    case rebuildEngine
    case surfacePausedState
}

/// Pure mapping of (session event, current state) → commands. Never touches
/// hardware; the whole interruption/route matrix is covered by unit tests.
nonisolated struct AudioInterruptionStateMachine {
    func handle(_ event: AudioSessionEvent, while state: RecordingState) -> [AudioCommand] {
        switch event {
        case .interruptionBegan:
            return state == .recording ? [.pauseCapture] : []

        case .interruptionEnded(let shouldResume):
            guard state == .pausedByInterruption else { return [] }
            // Even when the OS says resume, we only resume if we were paused by
            // an interruption. No resume flag → stay paused, show manual Resume.
            return shouldResume ? [.resumeCapture] : [.surfacePausedState]

        case .routeChanged(let reason):
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                return state == .recording ? [.reinstallTap] : []
            default:
                return []
            }

        case .mediaServicesReset:
            return state == .idle ? [] : [.rebuildEngine]
        }
    }
}
