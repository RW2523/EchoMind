import Foundation

/// Repeatable retrieval-quality eval (§8, V2). Indexes chunks with the real
/// embedder, runs queries, and scores how often a relevant chunk lands in top-K.
/// Used by both an XCTest gate and an on-device debug button so we can decide,
/// with numbers, whether NLEmbedding suffices or a MiniLM upgrade is warranted.
nonisolated struct RetrievalEval {
    struct Case: Sendable, Equatable {
        let query: String
        let expectedContains: String
    }

    struct Result: Sendable {
        let hits: Int
        let total: Int
        var score: Double { total == 0 ? 0 : Double(hits) / Double(total) }
        let misses: [String]
    }

    let embedder: any EmbeddingService
    let search: VectorSearch

    func score(chunks: [String], cases: [Case], k: Int = 3) async throws -> Result {
        guard !chunks.isEmpty, !cases.isEmpty else { return Result(hits: 0, total: cases.count, misses: []) }
        let vectors = try await embedder.embed(chunks)
        let ids = chunks.map { _ in UUID() }
        let candidates = Array(zip(ids, vectors)).map { (id: $0.0, vector: $0.1) }
        let textById = Dictionary(uniqueKeysWithValues: Array(zip(ids, chunks)))

        var hits = 0
        var misses: [String] = []
        for testCase in cases {
            guard let queryVector = try await embedder.embed([testCase.query]).first else { continue }
            let top = search.topK(query: queryVector, candidates: candidates, k: k)
            let matched = top.contains {
                (textById[$0.id] ?? "").localizedCaseInsensitiveContains(testCase.expectedContains)
            }
            if matched { hits += 1 } else { misses.append(testCase.query) }
        }
        return Result(hits: hits, total: cases.count, misses: misses)
    }

    /// A fixed suite over the sample handbook — deterministic, no bundled assets.
    static func handbookSuite(chunker: any TextChunking = TextChunker()) -> (chunks: [String], cases: [Case]) {
        #if DEBUG
        let text = DebugFixtures.sampleDocumentText
        #else
        let text = ""
        #endif
        let chunks = chunker.chunk(document: text, pageBreaks: [], sourceId: UUID()).map(\.text)
        let cases: [Case] = [
            .init(query: "what is the refund policy?", expectedContains: "30 days"),
            .init(query: "who leads the security team?", expectedContains: "Priya"),
            .init(query: "how much vacation do employees get?", expectedContains: "20 days"),
            .init(query: "when is customer support available?", expectedContains: "Monday"),
            .init(query: "do laptops need encryption?", expectedContains: "encryption"),
        ]
        return (chunks, cases)
    }
}
