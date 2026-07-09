import Testing
@testable import EchoMind

@Suite struct SentenceChunkerTests {
    /// Feed the whole text at once, then flush — the terminal state.
    private func chunkAll(_ text: String) -> [String] {
        var chunker = SentenceChunker()
        var out = chunker.push(cumulative: text)
        if let tail = chunker.flush() { out.append(tail) }
        return out
    }

    @Test func splitsBasicSentences() {
        #expect(chunkAll("Hello there. How are you?") == ["Hello there.", "How are you?"])
    }

    @Test func handlesExclamationAndQuestion() {
        #expect(chunkAll("Wow! Really? Yes.") == ["Wow!", "Really?", "Yes."])
    }

    @Test func doesNotSplitTitles() {
        #expect(chunkAll("Dr. Smith arrived. He was late.") == ["Dr. Smith arrived.", "He was late."])
    }

    @Test func doesNotSplitDecimals() {
        #expect(chunkAll("It costs 3.5 dollars. Cheap.") == ["It costs 3.5 dollars.", "Cheap."])
    }

    @Test func doesNotSplitDottedAbbreviations() {
        #expect(chunkAll("Use e.g. this one. Done.") == ["Use e.g. this one.", "Done."])
    }

    @Test func emitsOnlyCompletedSentencesWhileStreaming() {
        var chunker = SentenceChunker()
        #expect(chunker.push(cumulative: "Hello there") == [])             // no terminator yet
        #expect(chunker.push(cumulative: "Hello there. How are") == ["Hello there."])
        #expect(chunker.push(cumulative: "Hello there. How are you?") == [])  // '?' at end, unconfirmed
        #expect(chunker.push(cumulative: "Hello there. How are you? I") == ["How are you?"])
        #expect(chunker.flush() == "I")
    }

    @Test func flushReturnsNilWhenExhausted() {
        var chunker = SentenceChunker()
        _ = chunker.push(cumulative: "Done. ")
        _ = chunker.flush()
        #expect(chunker.flush() == nil)
    }

    @Test func emptyInputProducesNothing() {
        #expect(chunkAll("") == [])
    }
}
