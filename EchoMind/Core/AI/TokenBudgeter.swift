import Foundation

/// Token counting abstraction. The estimator is the V1 default; a native counter
/// backed by `LanguageModelSession.tokenCount(for:)` is the 26.4+ upgrade.
nonisolated protocol TokenCounting: Sendable {
    func count(_ text: String) -> Int
}

nonisolated struct EstimatedTokenCounter: TokenCounting {
    let charsPerToken: Double

    init(charsPerToken: Double = 3.5) { self.charsPerToken = charsPerToken }

    func count(_ text: String) -> Int {
        Int(ceil(Double(text.count) / charsPerToken))
    }
}

/// Every model call goes through this (§5.3). The 4,096 fallback lives HERE and
/// nowhere else — real `contextSize` can be injected from
/// `LanguageModelSession.contextSize` when adopted.
nonisolated struct TokenBudgeter: Sendable {
    static let fallbackContextSize = 4_096

    let contextSize: Int
    let counter: any TokenCounting

    init(contextSize: Int = TokenBudgeter.fallbackContextSize,
         counter: any TokenCounting = EstimatedTokenCounter()) {
        self.contextSize = contextSize
        self.counter = counter
    }

    func tokens(in text: String) -> Int { counter.count(text) }

    func fit(instructions: String, prompt: String, reservedOutput: Int) -> Bool {
        tokens(in: instructions) + tokens(in: prompt) + reservedOutput <= contextSize
    }

    /// Adds ranked items in order until the budget is exhausted; never splits an item.
    func pack(items: [String], budget: Int) -> (included: [String], usedTokens: Int) {
        var included: [String] = []
        var used = 0
        for item in items {
            let itemTokens = tokens(in: item)
            if used + itemTokens > budget { break }
            included.append(item)
            used += itemTokens
        }
        return (included, used)
    }
}
