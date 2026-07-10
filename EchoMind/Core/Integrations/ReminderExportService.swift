import Foundation
import EventKit

/// Writes action items into Apple Reminders (F5). Runs ONLY on an explicit user
/// tap — never in the background — which keeps the privacy story intact: reminders
/// are written locally by EventKit; EchoMind reads nothing back.
/// `@MainActor` protocol (like `VoiceInput`) because the first call presents the
/// system permission prompt.
@MainActor
protocol ReminderExporting {
    /// Create one reminder per draft in the user's default list.
    /// Returns how many were created.
    func export(_ drafts: [ReminderDraft]) async throws -> Int
}

nonisolated enum ReminderExportError: Error, Equatable {
    case accessDenied      // user declined Reminders access → point at Settings
    case nothingToExport
    case saveFailed
}

@MainActor
final class EventKitReminderExporter: ReminderExporting {
    private let store = EKEventStore()

    func export(_ drafts: [ReminderDraft]) async throws -> Int {
        guard !drafts.isEmpty else { throw ReminderExportError.nothingToExport }
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { throw ReminderExportError.accessDenied }
        guard let list = store.defaultCalendarForNewReminders() else {
            throw ReminderExportError.saveFailed
        }
        var saved = 0
        for draft in drafts {
            let reminder = EKReminder(eventStore: store)
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.calendar = list
            // Per-item best effort; one bad item shouldn't sink the batch.
            if (try? store.save(reminder, commit: false)) != nil { saved += 1 }
        }
        do { try store.commit() } catch { throw ReminderExportError.saveFailed }
        guard saved > 0 else { throw ReminderExportError.saveFailed }
        return saved
    }
}
