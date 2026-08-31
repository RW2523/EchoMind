import Foundation

/// Plain-text export of an Ask conversation — for taking the content outside the
/// app (analysis, sharing, archiving). Pure formatter, unit-testable; the view
/// model writes the result to a temp file for the share sheet.
nonisolated enum ChatExport {
    static let header = "EchoMind — Ask conversation"

    static func text(messages: [AskMessage], exportedAt: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines: [String] = [
            header,
            "Exported: \(formatter.string(from: exportedAt))",
            String(repeating: "—", count: 34),
            "",
        ]
        for message in messages {
            lines.append(message.role == .user ? "You:" : "EchoMind:")
            lines.append(message.content)
            if !message.sources.isEmpty {
                let titles = message.sources.map { source in
                    source.detail.map { "\(source.title) (\($0))" } ?? source.title
                }
                lines.append("[Sources: \(titles.joined(separator: "; "))]")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Stable, filesystem-safe file name, e.g. "EchoMind-Chat-2026-08-31.txt".
    static func fileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "EchoMind-Chat-\(formatter.string(from: date)).txt"
    }
}
