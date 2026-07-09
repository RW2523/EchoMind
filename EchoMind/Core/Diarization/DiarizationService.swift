import Foundation

/// Speaker diarization — "who spoke when" — over a retained recording (M3, V2 §C).
/// A post-hoc, on-device analysis run from the session detail on user request
/// (it's compute-heavy, so never automatic). Kept behind a protocol so the app is
/// package-independent; the FluidAudio conformer lives behind `#if canImport`.
nonisolated protocol DiarizationService: Sendable {
    /// True when a real diarization engine is linked in this build.
    var isAvailable: Bool { get }
    /// Analyse an audio file and return per-speaker time spans.
    func diarize(audioURL: URL) async throws -> DiarizationResult
}

nonisolated enum DiarizationError: Error, Equatable {
    case unavailable          // FluidAudio package not linked
    case audioUnreadable
    case failed(String)
}

/// Used when the FluidAudio package isn't linked. The session detail hides the
/// "Identify speakers" action when `isAvailable` is false, so this only guards the
/// programmatic path.
nonisolated struct UnavailableDiarizationService: DiarizationService {
    var isAvailable: Bool { false }
    func diarize(audioURL: URL) async throws -> DiarizationResult {
        throw DiarizationError.unavailable
    }
}
