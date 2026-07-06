import Foundation

nonisolated enum EmbeddingError: Error, Equatable {
    case unavailable
    case assetsUnavailable
    case emptyInput
    case zeroVector
}

/// Text embedding (§6.2). One L2-normalized vector per input. `dimension` is
/// resolved after asset load — never hardcoded. Implementations run off the
/// main actor. V1.1 escape hatch: a MiniLM Core ML model behind this protocol.
nonisolated protocol EmbeddingService: Sendable {
    var dimension: Int { get async throws }
    func embed(_ texts: [String]) async throws -> [[Float]]
    func prepareAssets() async throws
}
