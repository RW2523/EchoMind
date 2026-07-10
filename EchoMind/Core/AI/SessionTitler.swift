import Foundation

/// Names a session from its report (F3). Sessions are created with a date
/// placeholder ("Meeting Jul 9…"); once the summary exists, a short descriptive
/// title makes the Sessions list scannable. The pipeline only ever replaces the
/// placeholder — a user rename always wins.
nonisolated protocol SessionTitling: Sendable {
    /// A short human title for the meeting, or nil if one can't be produced.
    func title(overview: String, decisions: [String]) async -> String?
}

nonisolated struct MeetingTitler: SessionTitling {
    let gateway: any ModelGateway

    static let instructions = """
        You name meetings. Given meeting notes, reply with ONLY a title of 3 to 6 \
        words that says what the meeting was about. No quotes, no trailing \
        punctuation, and no generic words like "Meeting" or "Discussion" unless \
        they are essential.
        """
    static let maxTitleLength = 60

    func title(overview: String, decisions: [String]) async -> String? {
        let trimmedOverview = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOverview.isEmpty else { return nil }
        var prompt = trimmedOverview
        if !decisions.isEmpty {
            prompt += "\nDecisions: " + decisions.prefix(3).joined(separator: "; ")
        }
        let raw = try? await gateway.respond(instructions: Self.instructions,
                                             prompt: String(prompt.prefix(1_200)),
                                             maxOutputTokens: 20)
        return Self.sanitized(raw)
    }

    /// Model output → usable list title: first line only, label prefixes and wrapping
    /// quotes stripped, trailing punctuation dropped, length capped at a word
    /// boundary. Nil when nothing usable remains (caller keeps the placeholder).
    static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = text.components(separatedBy: .newlines).first { text = firstLine }
        for prefix in ["Title:", "title:", "TITLE:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”‘’.,:;!"))
        if text.count > maxTitleLength {
            let cut = String(text.prefix(maxTitleLength))
            // Trim back to the last full word so the cap never mid-word truncates.
            text = cut.contains(" ") ? cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)].trimmingCharacters(in: .whitespaces) : cut
        }
        guard text.count >= 3 else { return nil }
        let generic: Set<String> = ["meeting", "discussion", "untitled", "notes"]
        guard !generic.contains(text.lowercased()) else { return nil }
        return text
    }
}
