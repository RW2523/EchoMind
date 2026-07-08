import Foundation

// MLX-backed weight downloader. Like MLXEngine, compiled only when the package is
// linked; otherwise AppDependencies injects `UnavailableModelDownloadService`.
// `loadContainer` both downloads (into the HF cache) and reports progress; we drop
// the returned container — the engine re-opens from cache (no network) at load time
// — and drop a marker so "downloaded" survives independent of cache internals.

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon

nonisolated struct MLXModelDownloader: ModelDownloadService {
    var engineLinked: Bool { true }

    func isAvailable(_ model: LocalModel) async -> Bool { ModelStorage.isMarked(model) }

    func delete(_ model: LocalModel) async throws {
        try ModelStorage.unmark(model)
    }

    func download(_ model: LocalModel, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        do {
            let configuration = ModelConfiguration(id: model.huggingFaceRepo)
            _ = try await LLMModelFactory.shared.loadContainer(configuration: configuration) { progress in
                onProgress(progress.fractionCompleted)
            }
            try ModelStorage.mark(model)
            onProgress(1.0)
        } catch is CancellationError {
            throw ModelDownloadError.cancelled
        } catch {
            throw ModelDownloadError.failed(String(describing: error))
        }
    }
}
#endif
