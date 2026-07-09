import Testing
import Foundation
@testable import EchoMind

@Suite struct BM25Tests {
    @Test func tokenizeSplitsOnNonAlphanumerics() {
        #expect(BM25.tokenize("Hello, world-123!") == ["hello", "world", "123"])
    }

    @Test func ranksDocumentWithQueryTermsFirst() {
        let refund = UUID(), vacation = UUID(), security = UUID()
        let docs = [
            (id: refund, text: "The refund policy allows returns within thirty days."),
            (id: vacation, text: "Employees accrue vacation days and company holidays."),
            (id: security, text: "Laptops require full disk encryption for security."),
        ]
        let ranked = BM25().rank(query: "refund policy returns", documents: docs, k: 3)
        #expect(ranked.first?.id == refund)
    }

    @Test func emptyQueryReturnsNothing() {
        #expect(BM25().rank(query: "  ", documents: [(UUID(), "text here")], k: 5).isEmpty)
    }

    @Test func reciprocalRankFusionRewardsAgreement() {
        let a = UUID(), b = UUID(), c = UUID()
        // a is top in both rankings; c is last in both.
        let fused = BM25.reciprocalRankFusion([[a, b, c], [a, c, b]])
        #expect(fused.first?.id == a)
        #expect(fused.last?.id == c)
    }
}
