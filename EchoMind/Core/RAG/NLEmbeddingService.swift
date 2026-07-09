import Foundation
import NaturalLanguage
import Accelerate

/// EmbeddingService over `NLEmbedding.sentenceEmbedding` (§B1, V2). Unlike the
/// heavy NLContextualEmbedding E5 model (which won't compile in the Simulator),
/// this first-party sentence embedder ships with the OS and works EVERYWHERE —
/// simulator and device — with no package, no conversion, and no network.
///
/// A chunk (multiple sentences) is embedded by averaging its per-sentence vectors
/// then L2-normalizing, so dot product == cosine for VectorSearch.
actor NLEmbeddingService: EmbeddingService {
    private let language: NLLanguage
    private let embedding: NLEmbedding?

    init(language: NLLanguage = .english) {
        self.language = language
        self.embedding = NLEmbedding.sentenceEmbedding(for: language)
    }

    var dimension: Int {
        get async throws {
            guard let embedding else { throw EmbeddingError.unavailable }
            return embedding.dimension
        }
    }

    func prepareAssets() async throws {
        guard embedding != nil else { throw EmbeddingError.unavailable }
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        guard let embedding else { throw EmbeddingError.unavailable }
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        for (index, text) in texts.enumerated() {
            vectors.append(try pooledNormalized(text, embedding: embedding))
            if index % 32 == 31 { await Task.yield() }
        }
        return vectors
    }

    // MARK: - Pooling

    private func pooledNormalized(_ text: String, embedding: NLEmbedding) throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.emptyInput }
        let dimension = embedding.dimension

        var sum = [Float](repeating: 0, count: dimension)
        var count = 0
        for sentence in sentences(in: trimmed) {
            guard let vector = embedding.vector(for: sentence), vector.count == dimension else { continue }
            for i in 0..<dimension { sum[i] += Float(vector[i]) }
            count += 1
        }
        // Fallback: embed the whole text if per-sentence pooling produced nothing.
        if count == 0, let vector = embedding.vector(for: trimmed), vector.count == dimension {
            for i in 0..<dimension { sum[i] = Float(vector[i]) }
            count = 1
        }
        guard count > 0 else { throw EmbeddingError.zeroVector }

        var mean = sum.map { $0 / Float(count) }
        var norm: Float = 0
        vDSP_svesq(mean, 1, &norm, vDSP_Length(dimension))
        norm = sqrt(norm)
        guard norm > 1e-6 else { throw EmbeddingError.zeroVector }
        var divisor = norm
        var normalized = [Float](repeating: 0, count: dimension)
        vDSP_vsdiv(mean, 1, &divisor, &normalized, 1, vDSP_Length(dimension))
        return normalized
    }

    private func sentences(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let piece = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            return true
        }
        return result.isEmpty ? [text] : result
    }
}
