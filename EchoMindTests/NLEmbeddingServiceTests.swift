import Testing
import Foundation
@testable import EchoMind

@Suite struct NLEmbeddingServiceTests {
    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }

    @Test func producesNormalizedVectorsOfModelDimension() async throws {
        guard await EmbeddingTestSupport.modelAvailable() else { return }   // no asset on CI
        let service = NLEmbeddingService()
        let dimension = try await service.dimension
        #expect(dimension > 0)

        let vectors = try await service.embed(["The quick brown fox jumps over the lazy dog."])
        #expect(vectors.count == 1)
        #expect(vectors[0].count == dimension)

        let norm = (vectors[0].reduce(0) { $0 + $1 * $1 }).squareRoot()
        #expect(abs(norm - 1.0) < 1e-3)   // L2-normalized
    }

    @Test func semanticallySimilarTextsScoreHigher() async throws {
        guard await EmbeddingTestSupport.modelAvailable() else { return }   // no asset on CI
        let service = NLEmbeddingService()
        let vectors = try await service.embed([
            "The refund policy allows returns within thirty days of purchase.",
            "You can get your money back within a month of buying the item.",
            "The mountain weather in the Alps was cold and snowy that week.",
        ])
        let related = dot(vectors[0], vectors[1])     // refund ≈ money-back
        let unrelated = dot(vectors[0], vectors[2])    // refund vs weather
        #expect(related > unrelated)
    }

    @Test func emptyInputThrows() async {
        let service = NLEmbeddingService()
        await #expect(throws: (any Error).self) {
            _ = try await service.embed(["   "])
        }
    }
}
