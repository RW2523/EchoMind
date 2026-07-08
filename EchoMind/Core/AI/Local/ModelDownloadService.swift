import Foundation

/// Fetches model weights to on-device storage (V2 §B3). The one network capability
/// in the app — pinned Hugging Face repos, consent-gated, downloader-only in the
/// network-audit test. Kept behind a protocol so the UI is package-independent.
nonisolated protocol ModelDownloadService: Sendable {
    /// Downloads (or resumes) `model`, reporting fractional progress 0…1.
    func download(_ model: LocalModel, onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Removes cached weights for `model`.
    func delete(_ model: LocalModel) async throws
    /// Whether weights are already present on disk (no network).
    func isAvailable(_ model: LocalModel) async -> Bool
    /// True when a real inference engine is linked in this build.
    var engineLinked: Bool { get }
}

nonisolated enum ModelDownloadError: Error, Equatable {
    case engineNotLinked        // MLX package not added yet
    case failed(String)
    case cancelled
}

/// Used when the MLX package isn't linked: every download attempt explains the
/// missing prerequisite instead of failing opaquely. The whole app builds and runs
/// with only this; adding the package swaps in `MLXModelDownloader`.
nonisolated struct UnavailableModelDownloadService: ModelDownloadService {
    var engineLinked: Bool { false }
    func isAvailable(_ model: LocalModel) async -> Bool { false }
    func delete(_ model: LocalModel) async throws {}
    func download(_ model: LocalModel, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        throw ModelDownloadError.engineNotLinked
    }
}
