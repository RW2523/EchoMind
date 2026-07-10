import Foundation

/// Session title conventions (F3). New recordings get a date placeholder; once a
/// report exists, the auto-titler replaces it with a descriptive name. Lives in
/// Models/ so both the recording feature and the report pipeline share one source
/// of truth for "is this still the placeholder?".
nonisolated enum SessionNaming {
    /// Placeholder title given at recording time, e.g. "Meeting Jul 9, 2026 at 11:42 PM".
    static func defaultTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Meeting \(formatter.string(from: date))"
    }

    /// True when the title is still the recording-time placeholder — the only case
    /// the auto-titler may overwrite. Exact match against the recomputed placeholder,
    /// so a user rename (even one that starts with "Meeting") is never clobbered.
    /// If the device locale changed since creation the match fails and we simply
    /// keep the placeholder — fail-safe in the "never lose user input" direction.
    static func isPlaceholder(_ title: String, createdAt: Date) -> Bool {
        title == defaultTitle(createdAt)
    }
}
