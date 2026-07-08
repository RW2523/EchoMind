import Foundation

/// Pure Okapi BM25 keyword ranking over a chunk corpus (V2 §A3). Fixes the
/// classic embedding weakness — exact names, numbers, and acronyms — and is
/// fused with vector results via Reciprocal Rank Fusion.
nonisolated struct BM25 {
    let k1: Double
    let b: Double

    init(k1: Double = 1.5, b: Double = 0.75) {
        self.k1 = k1
        self.b = b
    }

    static func tokenize(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    func rank(query: String, documents: [(id: UUID, text: String)], k: Int) -> [(id: UUID, score: Double)] {
        guard !documents.isEmpty else { return [] }
        let queryTerms = Set(Self.tokenize(query))
        guard !queryTerms.isEmpty else { return [] }

        let docTokens = documents.map { Self.tokenize($0.text) }
        let docLengths = docTokens.map { Double($0.count) }
        let avgLength = max(1, docLengths.reduce(0, +) / Double(documents.count))
        let n = Double(documents.count)

        // Document frequency per query term.
        var docFreq: [String: Int] = [:]
        for term in queryTerms {
            var count = 0
            for tokens in docTokens where tokens.contains(term) { count += 1 }
            docFreq[term] = count
        }

        var scored: [(id: UUID, score: Double)] = []
        for (index, document) in documents.enumerated() {
            let tokens = docTokens[index]
            guard !tokens.isEmpty else { continue }
            var termCounts: [String: Int] = [:]
            for token in tokens where queryTerms.contains(token) { termCounts[token, default: 0] += 1 }

            var score = 0.0
            let lengthNorm = k1 * (1 - b + b * docLengths[index] / avgLength)
            for (term, freq) in termCounts {
                let df = Double(docFreq[term] ?? 0)
                guard df > 0 else { continue }
                let idf = log((n - df + 0.5) / (df + 0.5) + 1)
                let tf = Double(freq)
                score += idf * (tf * (k1 + 1)) / (tf + lengthNorm)
            }
            if score > 0 { scored.append((document.id, score)) }
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(k))
    }

    /// Reciprocal Rank Fusion of several ID rankings → fused ID → score.
    static func reciprocalRankFusion(_ rankings: [[UUID]], k: Double = 60) -> [(id: UUID, score: Double)] {
        var fused: [UUID: Double] = [:]
        var order: [UUID] = []               // first-appearance order, for stable ties
        for ranking in rankings {
            for (rank, id) in ranking.enumerated() {
                if fused[id] == nil { order.append(id) }
                fused[id, default: 0] += 1.0 / (k + Double(rank + 1))
            }
        }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        return order
            .map { (id: $0, score: fused[$0] ?? 0) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : position[$0.id]! < position[$1.id]! }
    }
}
