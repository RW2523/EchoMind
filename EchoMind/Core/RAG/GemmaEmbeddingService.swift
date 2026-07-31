import Foundation
import Accelerate

// EmbeddingGemma-300M retrieval embedder (M2). Compiled only when the MLX
// Embedders package is linked; until then AppDependencies uses NLEmbedding and the
// whole app builds/tests without it. The ONLY MLX-specific surface is `rawEmbed`
// — pooling into an L2-normalized vector (so dot == cosine for VectorSearch) is
// done here, correctly, regardless of the package API. If the MLXEmbedders API has
// drifted, `rawEmbed` is the single place to reconcile.
//
// Add in Xcode alongside MLXLLM: product **MLXEmbedders** from
//   https://github.com/ml-explore/mlx-swift-examples

#if canImport(MLXEmbedders)
import MLXEmbedders
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers
import MLX

actor GemmaEmbeddingService: EmbeddingService {
    private let model: LocalModel
    private var container: EmbedderModelContainer?

    init(model: LocalModel) { self.model = model }

    var dimension: Int {
        get async throws { model.contextSize }   // embedding models store dim here
    }

    func prepareAssets() async throws {
        if container != nil { return }
        do {
            container = try await EmbedderModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: ModelConfiguration(id: model.huggingFaceRepo))
        } catch {
            throw EmbeddingError.assetsUnavailable
        }
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { throw EmbeddingError.emptyInput }
        try await prepareAssets()
        let raw = try await rawEmbed(texts)
        return raw.map { l2Normalized($0) }
    }

    /// The one package-specific call. Returns one pooled (un-normalized) vector per
    /// input. Reconcile here if the MLXEmbedders API changed.
    private func rawEmbed(_ texts: [String]) async throws -> [[Float]] {
        guard let container else { throw EmbeddingError.assetsUnavailable }
        return await container.perform { context in
            texts.map { text in
                let tokens = context.tokenizer.encode(text: text, addSpecialTokens: true)
                let ids = MLXArray(tokens).reshaped([1, tokens.count])
                let output = context.model(ids, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)
                let pooled = context.pooling(output, normalize: false)
                pooled.eval()   // MLXArray must be evaluated before leaving the actor
                return pooled.asArray(Float.self)
            }
        }
    }

    private func l2Normalized(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        norm = sqrt(norm)
        guard norm > 1e-6 else { return v }
        var divisor = norm
        var out = [Float](repeating: 0, count: v.count)
        vDSP_vsdiv(v, 1, &divisor, &out, 1, vDSP_Length(v.count))
        return out
    }
}
#endif
