import Foundation
import Speech

/// Locale support check + on-device model install via AssetInventory (§3.3).
/// The download is OS-managed (no networking APIs in our own code) — see the
/// Phase 9 network-audit allowlist rationale.
nonisolated struct SpeechAssetManager: SpeechAssetManaging {
    func status(for locale: Locale) async throws -> SpeechAssetStatus {
        let supported = await SpeechTranscriber.supportedLocales
        // No models at all (the simulator ships none) — a distinct, honest state.
        guard !supported.isEmpty else { return .unavailable }
        let target = locale.identifier(.bcp47)
        guard supported.contains(where: { $0.identifier(.bcp47) == target }) else {
            return .unsupportedLocale
        }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(where: { $0.identifier(.bcp47) == target }) ? .installed : .needsDownload
    }

    func ensureInstalled(for locale: Locale) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let transcriber = SpeechTranscriber(
                        locale: locale,
                        transcriptionOptions: [],
                        reportingOptions: [.volatileResults],
                        attributeOptions: [.audioTimeRange])
                    _ = try await AssetInventory.reserve(locale: locale)
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        let progress = request.progress
                        let poller = Task {
                            while !Task.isCancelled && !progress.isFinished {
                                continuation.yield(progress.fractionCompleted)
                                try? await Task.sleep(nanoseconds: 200_000_000)
                            }
                        }
                        try await request.downloadAndInstall()
                        poller.cancel()
                    }
                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: TranscriptionError.assetDownloadFailed(String(describing: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
