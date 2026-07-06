import Testing
import Foundation
@testable import EchoMind

@Suite struct MapReducePlanTests {
    private func segment(chars: Int, start: TimeInterval = 0) -> SegmentText {
        SegmentText(text: String(repeating: "a ", count: chars / 2), startTime: start, endTime: start + 1)
    }

    @Test func singleSmallSegmentIsOneWindow() {
        let plan = MapReducePlan.make(segments: [segment(chars: 100)], budgeter: TokenBudgeter())
        #expect(plan.windows.count == 1)
    }

    @Test func packsWholeSegmentsUntilLimit() {
        // Each ~5000 chars ≈ 1429 tokens; two don't fit one 2,200-token window.
        let segs = [segment(chars: 5_000), segment(chars: 5_000)]
        let plan = MapReducePlan.make(segments: segs, budgeter: TokenBudgeter())
        #expect(plan.windows.count == 2)
    }

    @Test func noWindowExceedsTokenLimit() {
        let budgeter = TokenBudgeter()
        let segs = (0..<20).map { segment(chars: 2_000, start: TimeInterval($0)) }
        let plan = MapReducePlan.make(segments: segs, budgeter: budgeter)
        for window in plan.windows {
            let tokens = budgeter.tokens(in: window.map(\.text).joined(separator: " "))
            #expect(tokens <= SummaryPrompts.windowTokenLimit + 5)   // +overhead of the join spaces
        }
    }

    @Test func oversizedSingleSegmentSplitsOnSentences() {
        let budgeter = TokenBudgeter()
        // One ~30,000-char segment (~8,570 tokens) made of many sentences.
        let big = SegmentText(text: String(repeating: "This is a sentence. ", count: 1_500),
                              startTime: 0, endTime: 10)
        let plan = MapReducePlan.make(segments: [big], budgeter: budgeter)
        #expect(plan.windows.count > 1)
        for window in plan.windows {
            #expect(budgeter.tokens(in: window.map(\.text).joined()) <= SummaryPrompts.windowTokenLimit + 20)
        }
    }

    @Test func fixtureProducesMultipleBoundedWindows() {
        let budgeter = TokenBudgeter()
        let plan = MapReducePlan.make(segments: DebugFixtures.meetingSegments(), budgeter: budgeter)
        #expect(plan.windows.count > 1)
        let totalSegments = plan.windows.reduce(0) { $0 + $1.count }
        #expect(totalSegments == 150)
        for window in plan.windows {
            #expect(budgeter.tokens(in: window.map(\.text).joined(separator: " ")) <= SummaryPrompts.windowTokenLimit + 20)
        }
    }
}
