import Foundation
import AVFoundation

/// On-device speech transcription (§3.3). Consumes the engine's buffer stream
/// (passed in, so Core/Transcription has no audio dependency) and emits volatile
/// + finalized updates. Implemented by `SpeechAnalyzerTranscriber` over the
/// iOS 26 SpeechAnalyzer stack.
nonisolated protocol TranscriptionService: Sendable {
    func start(
        locale: Locale,
        audio: AsyncThrowingStream<AudioBufferBox, Error>
    ) async throws -> AsyncThrowingStream<TranscriptionUpdate, Error>

    /// Finalizes pending audio (flushes the volatile tail as final) then finishes.
    func stop() async
}

/// Locale asset availability for transcription.
nonisolated enum SpeechAssetStatus: Sendable, Equatable {
    case installed
    case needsDownload
    case unsupportedLocale
    /// No speech models are available at all (e.g. the iOS Simulator, which
    /// ships none) — distinct from a specific locale being unsupported.
    case unavailable
}

nonisolated protocol SpeechAssetManaging: Sendable {
    func status(for locale: Locale) async throws -> SpeechAssetStatus
    /// Emits progress 0…1 while installing; finishes on completion, throws on failure.
    func ensureInstalled(for locale: Locale) -> AsyncThrowingStream<Double, Error>
}
