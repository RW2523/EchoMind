import Foundation

#if DEBUG
/// Wires `RetrievalBenchmark` to real inputs so you can measure retrieval quality
/// two ways, on device, over your own data. A DEBUG-only dev tool.
enum RetrievalBenchmarkRunner {
    /// Deterministic baseline over the bundled sample handbook — no recorded data
    /// needed. Good for tracking an embedder change against a fixed corpus.
    static func handbook(embedder: any EmbeddingService,
                         chunker: any TextChunking = TextChunker()) async -> RetrievalBenchmark.Report? {
        let suite = RetrievalEval.handbookSuite(chunker: chunker)
        guard !suite.chunks.isEmpty else { return nil }
        let corpus = suite.chunks.map { RetrievalBenchmark.Doc(text: $0) }
        let cases = suite.cases.map { RetrievalBenchmark.Case(query: $0.query, expectTextContains: $0.expectedContains) }
        return try? await RetrievalBenchmark(embedder: embedder)
            .run(corpus: corpus, cases: cases, embedderName: "handbook")
    }

    /// Label-free eval over YOUR real meetings: each session's report overview
    /// becomes a query, and retrieval is judged on whether that session's own chunks
    /// come back. It's a proxy (a session should be findable from its own summary),
    /// but it needs zero hand-labeling — point it at a phone with real recordings.
    static func liveSelfRetrieval(sessions: any SessionRepository,
                                  chunks: any ChunkRepository,
                                  embedder: any EmbeddingService,
                                  embedderName: String = "live · self-retrieval") async -> RetrievalBenchmark.Report? {
        guard let allChunks = try? await chunks.fetchAll(), !allChunks.isEmpty,
              let allSessions = try? await sessions.fetchAll() else { return nil }
        let corpus = allChunks.map { RetrievalBenchmark.Doc(id: $0.id, sourceId: $0.sourceId, text: $0.text) }
        let sourcesWithChunks = Set(allChunks.map(\.sourceId))

        var cases: [RetrievalBenchmark.Case] = []
        for session in allSessions {
            guard sourcesWithChunks.contains(session.id),
                  let json = session.summaryJSON,
                  let summary = try? JSONDecoder().decode(MeetingSummary.self, from: Data(json.utf8)) else { continue }
            let overview = summary.overview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard overview.count >= 20 else { continue }   // too thin to be a fair query
            cases.append(.init(query: String(overview.prefix(400)), expectSourceId: session.id))
        }
        guard !cases.isEmpty else { return nil }
        return try? await RetrievalBenchmark(embedder: embedder)
            .run(corpus: corpus, cases: cases, embedderName: embedderName)
    }

    /// Hand-labeled eval over real indexed data: you supply question / expected-text
    /// pairs, scored against everything currently in the knowledge index.
    static func live(cases: [RetrievalBenchmark.Case],
                     chunks: any ChunkRepository,
                     embedder: any EmbeddingService,
                     embedderName: String = "live · labeled") async -> RetrievalBenchmark.Report? {
        guard !cases.isEmpty, let allChunks = try? await chunks.fetchAll(), !allChunks.isEmpty else { return nil }
        let corpus = allChunks.map { RetrievalBenchmark.Doc(id: $0.id, sourceId: $0.sourceId, text: $0.text) }
        return try? await RetrievalBenchmark(embedder: embedder)
            .run(corpus: corpus, cases: cases, embedderName: embedderName)
    }
}
#endif
