import Testing
import Foundation
@testable import EchoMind

/// Live Transcript fix: finalized lines must integrate EXACTLY ONCE. A replayed or
/// refined final for speech already accepted (same audio window) must never append
/// a second overlapping copy — that was the duplicated-transcript bug, and at
/// scale the layout-storm watchdog kill.
@Suite struct TranscriptAssemblyTests {
    private func act(last: (String, TimeInterval, TimeInterval),
                     new: (String, TimeInterval, TimeInterval)) -> TranscriptAssembly.Action {
        TranscriptAssembly.action(lastText: last.0, lastStart: last.1, lastEnd: last.2,
                                  newText: new.0, newStart: new.1, newEnd: new.2)
    }

    @Test func disjointUtterancesAppend() {
        #expect(act(last: ("hello there", 0, 2.0), new: ("how are you", 2.0, 4.0)) == .append)
        #expect(act(last: ("hello there", 0, 2.0), new: ("next thought", 5.0, 7.0)) == .append)
        // Small boundary sharing is still an append (adjacent utterances touch).
        #expect(act(last: ("hello", 0, 2.0), new: ("world", 1.98, 4.0)) == .append)
    }

    @Test func exactDuplicateIsDropped() {
        #expect(act(last: ("we ship friday", 0, 3.0), new: ("we ship friday", 0, 3.0)) == .drop)
        #expect(act(last: ("We ship Friday ", 0, 3.0), new: ("we ship friday", 0.1, 2.9)) == .drop)
    }

    @Test func refinementReplacesTheLastLine() {
        // The true final extends the earlier (misclassified) snapshot of the same window.
        #expect(act(last: ("we ship", 0, 2.0), new: ("we ship friday at noon", 0, 3.5)) == .replaceLast)
        #expect(act(last: ("", 0, 2.0), new: ("we ship friday", 0, 2.0)) == .replaceLast)
    }

    @Test func staleShorterSnapshotIsDropped() {
        // A late-arriving shorter version of speech we already have in full.
        #expect(act(last: ("we ship friday at noon", 0, 3.5), new: ("we ship friday", 0.2, 2.8)) == .drop)
    }

    @Test func overlappingButDifferentWordsAppends() {
        // Never lose genuinely different speech, even in an overlapping window.
        #expect(act(last: ("alice said yes", 0, 2.0), new: ("bob disagreed strongly", 1.5, 4.0)) == .append)
    }

    @Test func exactlyOnceOverASequence() {
        // Simulate the field bug: volatile-misclassified final, then the true final,
        // then a fresh utterance — result must be TWO lines, no duplication.
        var lines: [(text: String, start: TimeInterval, end: TimeInterval)] = []
        let finals: [(String, TimeInterval, TimeInterval)] = [
            ("the budget is", 0, 1.8),                 // misclassified snapshot
            ("the budget is approved today", 0, 3.0),  // true final, same window
            ("the budget is approved today", 0, 3.0),  // replayed final
            ("next we discussed hiring", 3.1, 6.0),    // new utterance
        ]
        for f in finals {
            if let last = lines.last {
                switch TranscriptAssembly.action(lastText: last.text, lastStart: last.start, lastEnd: last.end,
                                                 newText: f.0, newStart: f.1, newEnd: f.2) {
                case .drop: continue
                case .replaceLast: lines[lines.count - 1] = (f.0, min(last.start, f.1), max(last.end, f.2)); continue
                case .append: break
                }
            }
            lines.append((f.0, f.1, f.2))
        }
        #expect(lines.map(\.text) == ["the budget is approved today", "next we discussed hiring"])
    }
}
