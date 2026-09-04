import Foundation

// The ONLY file that touches the MLX Swift package. It is compiled solely when
// the package is linked (`#if canImport(MLXLLM)`), so the whole app builds and
// tests today with the package absent; adding it in Xcode lights this up with no
// other change. If the MLX API has drifted by the time the package lands, THIS is
// the single place to reconcile — everything above it speaks `LocalLLMEngine`.
//
// Add in Xcode: File ▸ Add Package Dependencies… ▸
//   https://github.com/ml-explore/mlx-swift-examples
//   → add products: MLXLLM, MLXLMCommon  (pulls in mlx-swift transitively)

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// On-device LLM via Apple's MLX (Metal) runtime. An actor: weight loading and
/// generation are serialized, and `container` state is race-free.
actor MLXEngine: LocalLLMEngine {
    let model: LocalModel
    private var container: ModelContainer?

    init(model: LocalModel = LocalModelCatalog.default) {
        self.model = model
    }

    nonisolated var contextSize: Int { model.contextSize }

    func isLoaded() async -> Bool { container != nil }

    func load() async throws {
        if container != nil { return }
        do {
            // #hubDownloader / #huggingFaceTokenizerLoader are MLXHuggingFace macros
            // adapting the HuggingFace hub client to MLX's Downloader/TokenizerLoader
            // seams (the 3.x replacement for the old configuration-only overload).
            let configuration = ModelConfiguration(id: model.huggingFaceRepo)
            container = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration)
        } catch {
            throw LocalLLMEngineError.loadFailed(String(describing: error))
        }
    }

    func complete(messages: [LLMMessage], maxTokens: Int) async throws -> String {
        guard let container else { throw LocalLLMEngineError.notLoaded }
        let chat = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        do {
            return try await container.perform { context in
                let input = try await context.processor.prepare(input: UserInput(messages: chat))
                let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.4)
                // The callback is the ONLY cancellation point in MLX's
                // synchronous generation loop: without the isCancelled check, a
                // barge-in left the discarded generation running to its full
                // token budget, serialized ahead of the next answer (voice hang).
                let result = try MLXLMCommon.generate(
                    input: input, parameters: parameters, context: context) { (_: [Int]) in
                    Task.isCancelled ? .stop : .more
                }
                try Task.checkCancellation()
                return result.output
            }
        } catch {
            throw LocalLLMEngineError.generationFailed(String(describing: error))
        }
    }
}
#endif
