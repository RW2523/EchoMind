import Testing
import Foundation
@testable import EchoMind

@Suite struct SummarizerRetryTests {
    private func segment(chars: Int, start: TimeInterval = 0) -> SegmentText {
        SegmentText(text: String(repeating: "a ", count: chars / 2), startTime: start, endTime: start + 1)
    }

    private let noProgress: @Sendable (SummarizerProgress) -> Void = { _ in }

    @Test func skipMapUsesGenerateOnceForSmallTranscript() async throws {
        let gateway = MockModelGateway()
        let summarizer = MapReduceSummarizer(gateway: gateway)
        _ = try await summarizer.summarize(segments: [segment(chars: 400)], onProgress: noProgress)
        let counts = await gateway.counts()
        #expect(counts.generate == 1)
        #expect(counts.respond == 0)
    }

    @Test func multiWindowRunsMapThenReduce() async throws {
        let gateway = MockModelGateway()
        let summarizer = MapReduceSummarizer(gateway: gateway)
        _ = try await summarizer.summarize(segments: [segment(chars: 5_000), segment(chars: 5_000)],
                                           onProgress: noProgress)
        let counts = await gateway.counts()
        #expect(counts.respond == 2)   // one map per window
        #expect(counts.generate == 1)  // one reduce
    }

    @Test func reduceOverflowTriggersIntermediateReduceThenSucceeds() async throws {
        // First reduce (generate) overflows once; summarizer merges partials via
        // respond and retries generate.
        let gateway = MockModelGateway(overflowGenerate: 1)
        let summarizer = MapReduceSummarizer(gateway: gateway)
        let summary = try await summarizer.summarize(
            segments: [segment(chars: 5_000), segment(chars: 5_000)], onProgress: noProgress)
        #expect(summary.overview == "An overview.")
        let counts = await gateway.counts()
        #expect(counts.generate == 2)   // 1 failed + 1 succeeded
        #expect(counts.respond > 2)     // 2 map + merge calls
    }

    @Test func persistentReduceOverflowThrowsTooLong() async {
        // Skip-map reduce overflows and has no re-split → clear error, never crash.
        let gateway = MockModelGateway(overflowGenerate: 1)
        let summarizer = MapReduceSummarizer(gateway: gateway)
        await #expect(throws: SummarizerError.tooLong) {
            _ = try await summarizer.summarize(segments: [self.segment(chars: 400)], onProgress: self.noProgress)
        }
    }

    @Test func emptyTranscriptThrowsNotEnoughContent() async {
        let summarizer = MapReduceSummarizer(gateway: MockModelGateway())
        await #expect(throws: SummarizerError.notEnoughContent) {
            _ = try await summarizer.summarize(segments: [], onProgress: self.noProgress)
        }
    }
}
