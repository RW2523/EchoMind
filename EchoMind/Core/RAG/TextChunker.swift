import Foundation
import NaturalLanguage

nonisolated protocol TextChunking: Sendable {
    func chunk(document text: String,
               pageBreaks: [(pageNumber: Int, utf16Offset: Int)],
               sourceId: UUID) -> [TextChunk]
    func chunk(segments: [(text: String, startTime: TimeInterval)],
               sourceId: UUID) -> [TextChunk]
}

/// Pure, synchronous sentence-boundary chunking (§6.3): ~200-word chunks with
/// ~40-word overlap (stride ≈160). Never splits mid-sentence, except a single
/// sentence > 300 words is hard-split on word boundaries.
nonisolated struct TextChunker: TextChunking {
    let targetWords = 200
    let overlapWords = 40
    let hardSplitWords = 300

    func chunk(document text: String,
               pageBreaks: [(pageNumber: Int, utf16Offset: Int)],
               sourceId: UUID) -> [TextChunk] {
        let sentences = preprocess(sentenceList(in: text))
        return assemble(sentences, sourceId: sourceId, sourceType: .document) { offset in
            (Self.pageNumber(forOffset: offset, breaks: pageBreaks), nil)
        }
    }

    func chunk(segments: [(text: String, startTime: TimeInterval)],
               sourceId: UUID) -> [TextChunk] {
        var combined = ""
        var breaks: [(startTime: TimeInterval, utf16Offset: Int)] = []
        for (index, segment) in segments.enumerated() {
            breaks.append((segment.startTime, combined.utf16.count))
            combined += segment.text
            if index < segments.count - 1 { combined += " " }
        }
        let sentences = preprocess(sentenceList(in: combined))
        return assemble(sentences, sourceId: sourceId, sourceType: .session) { offset in
            (nil, Self.timestamp(forOffset: offset, breaks: breaks))
        }
    }

    // MARK: - Sentence splitting

    private func sentenceList(in text: String) -> [(text: String, utf16Start: Int)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [(String, Int)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                let offset = text.utf16.distance(from: text.utf16.startIndex,
                                                 to: range.lowerBound.samePosition(in: text.utf16) ?? text.utf16.startIndex)
                sentences.append((sentence, offset))
            }
            return true
        }
        return sentences
    }

    private func preprocess(_ sentences: [(text: String, utf16Start: Int)]) -> [(text: String, utf16Start: Int)] {
        var output: [(String, Int)] = []
        for sentence in sentences {
            if wordCount(sentence.text) > hardSplitWords {
                let words = sentence.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                var index = 0
                while index < words.count {
                    let piece = words[index..<min(index + targetWords, words.count)].joined(separator: " ")
                    output.append((piece, sentence.utf16Start))
                    index += targetWords
                }
            } else {
                output.append(sentence)
            }
        }
        return output
    }

    // MARK: - Assembly

    private func assemble(_ sentences: [(text: String, utf16Start: Int)],
                          sourceId: UUID,
                          sourceType: SourceType,
                          metaFor: (Int) -> (page: Int?, timestamp: TimeInterval?)) -> [TextChunk] {
        guard !sentences.isEmpty else { return [] }
        var chunks: [TextChunk] = []
        var start = 0
        var chunkIndex = 0

        while start < sentences.count {
            var end = start
            var words = 0
            while end < sentences.count {
                let count = wordCount(sentences[end].text)
                if words > 0 && words + count > targetWords { break }
                words += count
                end += 1
                if words >= targetWords { break }
            }
            if end == start { end = start + 1 }

            let group = Array(sentences[start..<end])
            let meta = metaFor(group[0].utf16Start)
            chunks.append(TextChunk(text: group.map(\.text).joined(separator: " "),
                                    sourceId: sourceId, sourceType: sourceType,
                                    chunkIndex: chunkIndex, pageNumber: meta.page, timestamp: meta.timestamp))
            chunkIndex += 1

            if end >= sentences.count { break }

            // Next chunk starts with trailing sentences totaling ~overlapWords.
            var overlap = 0
            var overlapStart = end
            while overlapStart > start + 1 && overlap < overlapWords {
                overlapStart -= 1
                overlap += wordCount(sentences[overlapStart].text)
            }
            start = max(start + 1, overlapStart)
        }
        return chunks
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - Metadata lookup

    static func pageNumber(forOffset offset: Int, breaks: [(pageNumber: Int, utf16Offset: Int)]) -> Int? {
        guard !breaks.isEmpty else { return nil }
        var page = breaks[0].pageNumber
        for entry in breaks where offset >= entry.utf16Offset { page = entry.pageNumber }
        return page
    }

    static func timestamp(forOffset offset: Int, breaks: [(startTime: TimeInterval, utf16Offset: Int)]) -> TimeInterval? {
        guard !breaks.isEmpty else { return nil }
        var time = breaks[0].startTime
        for entry in breaks where offset >= entry.utf16Offset { time = entry.startTime }
        return time
    }
}
