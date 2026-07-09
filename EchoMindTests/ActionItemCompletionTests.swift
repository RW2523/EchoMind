import Testing
import Foundation
@testable import EchoMind

/// Bug 8: action-item checkmarks were keyed by position, so regenerating a report
/// (which can reorder items) moved checks onto the wrong items. Completion is now
/// keyed by item text.
@Suite struct ActionItemCompletionTests {
    private func item(_ t: String) -> MeetingSummary.ActionItem { .init(text: t, owner: nil) }

    @Test func checkSurvivesReordering() {
        let original = [item("Ship release notes"), item("Book the venue"), item("Email the team")]
        // User checks "Book the venue".
        let json = ActionItemCompletion.json(items: original, flags: [false, true, false])

        // Regeneration reorders the same items.
        let reordered = [item("Email the team"), item("Ship release notes"), item("Book the venue")]
        let flags = ActionItemCompletion.flags(from: json, items: reordered)
        #expect(flags == [false, false, true])   // still "Book the venue"
    }

    @Test func newItemsDefaultUnchecked() {
        let json = ActionItemCompletion.json(items: [item("A")], flags: [true])
        let flags = ActionItemCompletion.flags(from: json, items: [item("A"), item("B (new)")])
        #expect(flags == [true, false])
    }

    @Test func readsLegacyPositionalBoolFormat() {
        // Old persisted shape: a JSON array of Bool aligned to the item order.
        let legacy = "[false,true]"
        let items = [item("First"), item("Second")]
        let flags = ActionItemCompletion.flags(from: legacy, items: items)
        #expect(flags == [false, true])
    }

    @Test func normalizationIgnoresCaseAndWhitespace() {
        let json = ActionItemCompletion.json(items: [item("Do The Thing")], flags: [true])
        let flags = ActionItemCompletion.flags(from: json, items: [item("  do the thing ")])
        #expect(flags == [true])
    }

    @Test func emptyAndMissingAreUnchecked() {
        #expect(ActionItemCompletion.flags(from: nil, items: [item("A")]) == [false])
        #expect(ActionItemCompletion.flags(from: "[]", items: [item("A")]) == [false])
    }
}
