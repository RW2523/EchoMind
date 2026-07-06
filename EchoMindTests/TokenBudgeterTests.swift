import Testing
@testable import EchoMind

@Suite struct TokenBudgeterTests {
    @Test func estimatorRoundsUp() {
        let counter = EstimatedTokenCounter(charsPerToken: 3.5)
        #expect(counter.count("") == 0)
        #expect(counter.count(String(repeating: "a", count: 7)) == 2)   // 7/3.5 = 2
        #expect(counter.count(String(repeating: "a", count: 8)) == 3)   // ceil(8/3.5) = 3
    }

    @Test func fitRespectsContextSize() {
        let budgeter = TokenBudgeter(contextSize: 100, counter: EstimatedTokenCounter(charsPerToken: 1))
        #expect(budgeter.fit(instructions: String(repeating: "a", count: 40),
                             prompt: String(repeating: "b", count: 40), reservedOutput: 10) == true)   // 90 ≤ 100
        #expect(budgeter.fit(instructions: String(repeating: "a", count: 60),
                             prompt: String(repeating: "b", count: 40), reservedOutput: 10) == false)  // 110 > 100
    }

    @Test func packStopsAtBudgetWithoutSplitting() {
        let budgeter = TokenBudgeter(counter: EstimatedTokenCounter(charsPerToken: 1))
        let items = ["aaaa", "bbbb", "cccc"]   // 4 tokens each
        let result = budgeter.pack(items: items, budget: 9)
        #expect(result.included == ["aaaa", "bbbb"])   // 8 ≤ 9; third would be 12
        #expect(result.usedTokens == 8)
    }

    @Test func fallbackContextSizeIsTheSinglePlace() {
        #expect(TokenBudgeter().contextSize == 4_096)
    }
}
