import Foundation
import NaturalLanguage
import Accelerate

/// EmbeddingService over NLContextualEmbedding (§6.3): token embeddings ->
/// mean-pool -> L2-normalize. An actor, so it never runs on @MainActor.
actor NLContextualEmbeddingService: EmbeddingService {
    private let language: NLLanguage
    private var model: NLContextualEmbedding?
    private var loaded = false

    init(language: NLLanguage = .english) {
        self.language = language
    }

    var dimension: Int {
        get async throws {
            try await prepareAssets()
            return try requireModel().dimension
        }
    }

    func prepareAssets() async throws {
        let model = try requireModel()
        if !model.hasAvailableAssets {
            let result = try await model.requestAssets()
            guard result == .available else { throw EmbeddingError.assetsUnavailable }
        }
        if !loaded {
            try model.load()
            loaded = true
        }
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        try await prepareAssets()
        let model = try requireModel()
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        for (index, text) in texts.enumerated() {
            vectors.append(try meanPooledNormalized(text, model: model))
            if index % 16 == 15 { await Task.yield() }
        }
        return vectors
    }

    // MARK: - Helpers

    private func requireModel() throws -> NLContextualEmbedding {
        if let model { return model }
        guard let created = NLContextualEmbedding(language: language) else {
            throw EmbeddingError.unavailable
        }
        model = created
        return created
    }

    private func meanPooledNormalized(_ text: String, model: NLContextualEmbedding) throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyInput }

        let result = try model.embeddingResult(for: trimmed, language: language)
        let dimension = model.dimension
        var sum = [Float](repeating: 0, count: dimension)
        var tokenCount = 0
        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            let limit = min(dimension, vector.count)
            for i in 0..<limit { sum[i] += Float(vector[i]) }
            tokenCount += 1
            return true
        }
        guard tokenCount > 0 else { throw EmbeddingError.emptyInput }

        var mean = sum.map { $0 / Float(tokenCount) }
        var norm: Float = 0
        vDSP_svesq(mean, 1, &norm, vDSP_Length(dimension))
        norm = sqrt(norm)
        guard norm > 1e-6 else { throw EmbeddingError.zeroVector }
        var divisor = norm
        var normalized = [Float](repeating: 0, count: dimension)
        vDSP_vsdiv(mean, 1, &divisor, &normalized, 1, vDSP_Length(dimension))
        return normalized
    }
}
