import Foundation
import AVFoundation
import Speech

/// Microphone + speech authorization, normalized to `PermissionState`.
/// Reads live status on demand (never caches) so Phase 3 always sees truth even
/// if the user flips permissions in iOS Settings while the app is backgrounded.
nonisolated protocol PermissionManaging: Sendable {
    func microphoneState() -> PermissionState
    func speechState() -> PermissionState
    func requestMicrophone() async -> PermissionState
    func requestSpeech() async -> PermissionState
}

/// Live implementation.
///
/// NOTE: `SFSpeechRecognizer` is used here ONLY for its authorization API —
/// SpeechTranscriber (Phase 3) rides the same speech-recognition authorization
/// and there is no SpeechAnalyzer-native request call. No transcription path may
/// touch `SFSpeechRecognizer` beyond `authorizationStatus()` / `requestAuthorization`.
nonisolated struct PermissionManager: PermissionManaging {
    func microphoneState() -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .notDetermined
        case .granted: return .granted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    func speechState() -> PermissionState {
        Self.map(SFSpeechRecognizer.authorizationStatus())
    }

    func requestMicrophone() async -> PermissionState {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    func requestSpeech() async -> PermissionState {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}

/// Deterministic stub for previews and unit tests.
nonisolated struct StubPermissionManager: PermissionManaging {
    var microphone: PermissionState = .notDetermined
    var speech: PermissionState = .notDetermined
    func microphoneState() -> PermissionState { microphone }
    func speechState() -> PermissionState { speech }
    func requestMicrophone() async -> PermissionState { microphone }
    func requestSpeech() async -> PermissionState { speech }
}
