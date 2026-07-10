import Testing
import Foundation
@testable import EchoMind

/// F5: action items → Reminders. The mapping is pure; EventKit itself is
/// device-only and exercised via the checklist.
@Suite struct ReminderDraftTests {
    private func item(_ t: String, owner: String? = nil) -> MeetingSummary.ActionItem {
        .init(text: t, owner: owner)
    }

    @Test func mapsTextOwnerAndSourceMeeting() {
        let drafts = ReminderDrafts.make(from: [item("Ship the release notes", owner: "Sam")],
                                         sessionTitle: "Q3 Launch Planning")
        #expect(drafts.count == 1)
        #expect(drafts[0].title == "Ship the release notes")
        #expect(drafts[0].notes.contains("From meeting: Q3 Launch Planning"))
        #expect(drafts[0].notes.contains("Owner: Sam"))
    }

    @Test func omitsOwnerLineWhenAbsentOrBlank() {
        let drafts = ReminderDrafts.make(from: [item("Book the venue"), item("Email team", owner: "  ")],
                                         sessionTitle: "Offsite")
        #expect(drafts.count == 2)
        #expect(!drafts[0].notes.contains("Owner:"))
        #expect(!drafts[1].notes.contains("Owner:"))
    }

    @Test func dropsEmptyItemsAndTrimsWhitespace() {
        let drafts = ReminderDrafts.make(from: [item("   "), item("  Real task  ")],
                                         sessionTitle: "Sync")
        #expect(drafts.count == 1)
        #expect(drafts[0].title == "Real task")
    }

    @Test func emptyInputMakesNoDrafts() {
        #expect(ReminderDrafts.make(from: [], sessionTitle: "Anything").isEmpty)
    }
}
