import Foundation

/// What one action item becomes in Apple Reminders (F5). Pure value type so the
/// mapping is unit-testable without EventKit.
nonisolated struct ReminderDraft: Equatable, Sendable {
    let title: String
    let notes: String
}

nonisolated enum ReminderDrafts {
    /// Action items → reminder drafts. Empty/whitespace items are dropped; the
    /// owner and source meeting land in the notes so the reminder stands alone.
    static func make(from items: [MeetingSummary.ActionItem], sessionTitle: String) -> [ReminderDraft] {
        items.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var notes = "From meeting: \(sessionTitle)"
            if let owner = item.owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
                notes += "\nOwner: \(owner)"
            }
            notes += "\nAdded by EchoMind"
            return ReminderDraft(title: text, notes: notes)
        }
    }
}
