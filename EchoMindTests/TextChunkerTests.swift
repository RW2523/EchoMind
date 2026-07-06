import Testing
import Foundation
@testable import EchoMind

@Suite struct TextChunkerTests {
    private let chunker = TextChunker()

    private func words(_ n: Int, prefix: String = "word") -> String {
        (0..<n).map { "\(prefix)\($0)" }.joined(separator: " ") + "."
    }

    @Test func emptyInputProducesNoChunks() {
        #expect(chunker.chunk(document: "", pageBreaks: [], sourceId: UUID()).isEmpty)
        #expect(chunker.chunk(document: "   \n  ", pageBreaks: [], sourceId: UUID()).isEmpty)
    }

    @Test func shortTextIsOneChunk() {
        let chunks = chunker.chunk(document: "One sentence here. Another one.", pageBreaks: [], sourceId: UUID())
        #expect(chunks.count == 1)
        #expect(chunks[0].chunkIndex == 0)
        #expect(chunks[0].sourceType == .document)
    }

    @Test func longTextSplitsIntoMultipleChunksWithMonotonicIndex() {
        // ~10 sentences of ~60 words each ≈ 600 words -> several ~200-word chunks.
        let text = (0..<10).map { _ in words(60) }.joined(separator: " ")
        let chunks = chunker.chunk(document: text, pageBreaks: [(1, 0)], sourceId: UUID())
        #expect(chunks.count > 1)
        #expect(chunks.map(\.chunkIndex) == Array(0..<chunks.count))
    }

    @Test func consecutiveChunksOverlap() {
        // Realistic sentences (capitalized, unique marker word) so NLTokenizer
        // splits them properly and chunks contain many sentences.
        let text = (0..<80).map { i in "Marker\(i) alpha beta gamma delta epsilon zeta." }
            .joined(separator: " ")
        let chunks = chunker.chunk(document: text, pageBreaks: [], sourceId: UUID())
        #expect(chunks.count >= 2)
        // Chunk 1 begins a few sentences before chunk 0 ends, so chunk 1's first
        // marker word also appears in chunk 0 (the ~40-word overlap).
        let firstWordOfChunk1 = chunks[1].text.split(separator: " ").first.map(String.init) ?? ""
        #expect(firstWordOfChunk1.hasPrefix("Marker"))
        #expect(chunks[0].text.contains(firstWordOfChunk1))
    }

    @Test func neverSplitsMidSentence() {
        let text = (0..<8).map { i in "Sentence number \(i) has several words in it here." }.joined(separator: " ")
        let chunks = chunker.chunk(document: text, pageBreaks: [], sourceId: UUID())
        // Every chunk ends at a sentence boundary (with a period).
        for chunk in chunks {
            #expect(chunk.text.trimmingCharacters(in: .whitespaces).hasSuffix(".") == true)
        }
    }

    @Test func pageNumberFromBreaks() {
        // Page 1 at offset 0, page 2 starts partway through.
        let page1 = words(30)
        let page2 = words(30)
        let text = page1 + "\n\n" + page2
        let breaks: [(pageNumber: Int, utf16Offset: Int)] = [(1, 0), (2, page1.utf16.count + 2)]
        let chunks = chunker.chunk(document: text, pageBreaks: breaks, sourceId: UUID())
        #expect(chunks.first?.pageNumber == 1)
    }

    @Test func sessionChunksCarryTimestamp() {
        let segments: [(text: String, startTime: TimeInterval)] = [
            (words(30), 0),
            (words(30), 15),
        ]
        let chunks = chunker.chunk(segments: segments, sourceId: UUID())
        #expect(chunks.first?.timestamp == 0)
        #expect(chunks.allSatisfy { $0.sourceType == .session })
    }

    @Test func giantSentenceIsHardSplit() {
        // One 500-word "sentence" (no periods) exceeds hardSplitWords (300).
        let giant = (0..<500).map { "w\($0)" }.joined(separator: " ")
        let chunks = chunker.chunk(document: giant, pageBreaks: [], sourceId: UUID())
        #expect(chunks.count > 1)
    }
}
