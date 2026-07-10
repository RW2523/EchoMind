import Testing
import Foundation
@testable import EchoMind

@Suite struct RetrievalBenchmarkTests {

    // MARK: - Metric math (deterministic, no embedder)

    private func outcome(_ query: String, relevant: Int, firstRank: Int?, recall: [Int: Double]) -> RetrievalBenchmark.QueryOutcome {
        .init(query: query, relevantInCorpus: relevant, firstRelevantRank: firstRank, recallAtK: recall)
    }

    @Test func reciprocalRankIsInverseOfFirstHit() {
        #expect(outcome("a", relevant: 1, firstRank: 1, recall: [:]).reciprocalRank == 1.0)
        #expect(outcome("b", relevant: 1, firstRank: 4, recall: [:]).reciprocalRank == 0.25)
        #expect(outcome("c", relevant: 1, firstRank: nil, recall: [:]).reciprocalRank == 0.0)
    }

    @Test func meanRecallAndMRRAverageOnlyLabeledCases() {
        let report = RetrievalBenchmark.Report(
            embedderName: "t", corpusSize: 10, ks: [1, 6],
            perQuery: [
                outcome("hit@1", relevant: 1, firstRank: 1, recall: [1: 1.0, 6: 1.0]),
                outcome("hit@3", relevant: 1, firstRank: 3, recall: [1: 0.0, 6: 1.0]),
                outcome("unlabeled", relevant: 0, firstRank: nil, recall: [:]),   // excluded
            ],
            unlabeled: ["unlabeled"])
        // Averages over the 2 labeled cases only.
        #expect(report.meanRecallAtK[1] == 0.5)          // (1.0 + 0.0) / 2
        #expect(report.meanRecallAtK[6] == 1.0)          // (1.0 + 1.0) / 2
        #expect(abs(report.mrr - (1.0 + 1.0 / 3.0) / 2.0) < 1e-9)
    }

    @Test func emptyReportDoesNotDivideByZero() {
        let report = RetrievalBenchmark.Report(embedderName: "t", corpusSize: 0, ks: [6],
                                               perQuery: [], unlabeled: [])
        #expect(report.mrr == 0)
        #expect(report.meanRecallAtK.isEmpty)
    }

    // MARK: - End-to-end over the handbook (real NLEmbedding + hybrid pipeline)

    @Test func handbookBenchmarkMeetsRecallGate() async throws {
        guard await EmbeddingTestSupport.modelAvailable() else { return }   // no asset on CI
        let report = try #require(
            await RetrievalBenchmarkRunner.handbook(embedder: NLEmbeddingService()))

        // The full report prints into the Xcode test log / .xcresult; on device the
        // same text shows under Settings ▸ Debug ▸ "Run retrieval benchmark". In CI,
        // the threshold assertion below is the signal — you don't parse numbers there.
        print("\n" + report.formatted() + "\n")

        // recall@6 is recall over the exact chunks the app feeds the model. If this
        // slips, that's the signal to wire EmbeddingGemma (V2 §B1).
        let recallAt6 = try #require(report.meanRecallAtK[6])
        #expect(recallAt6 >= 0.6, "recall@6 \(recallAt6); report:\n\(report.formatted())")
        #expect(report.mrr > 0)
        #expect(report.unlabeled.isEmpty, "handbook cases should all be labelable")
    }

    @Test func unlabeledCasesAreFlaggedAndExcluded() async throws {
        guard await EmbeddingTestSupport.modelAvailable() else { return }   // no asset on CI
        let corpus = [
            RetrievalBenchmark.Doc(text: "The refund window is 30 days from purchase."),
            RetrievalBenchmark.Doc(text: "Support is available Monday to Friday."),
        ]
        let cases = [
            RetrievalBenchmark.Case(query: "refund policy", expectTextContains: "30 days"),
            RetrievalBenchmark.Case(query: "nonsense", expectTextContains: "zzz-not-in-corpus"),
        ]
        let report = try await RetrievalBenchmark(embedder: NLEmbeddingService())
            .run(corpus: corpus, cases: cases)
        #expect(report.unlabeled == ["nonsense"])
        // The unlabeled case is excluded, so the mean reflects only the real one.
        #expect(report.meanRecallAtK[6] == 1.0)
    }
}
