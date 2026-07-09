import Foundation

/// Persistence for action-item checkmarks (R1). Completion is keyed by a normalized
/// hash of the item's *text*, not its position, so a user's checkmarks survive a
/// report regeneration that reorders or replaces items. Persisted as a JSON array of
/// the completed items' normalized texts.
///
/// Back-compat: earlier builds stored a positional `[Bool]`. `completedSet` still
/// reads that shape by mapping the flags onto the current items; the next toggle
/// rewrites the session in the stable text-keyed format.
nonisolated enum ActionItemCompletion {
    static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The set of completed item keys, from either the new (`[String]`) or the legacy
    /// (`[Bool]`) persisted format. `items` is only needed to interpret the legacy one.
    static func completedSet(from json: String?, items: [MeetingSummary.ActionItem]) -> Set<String> {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        if let texts = try? JSONDecoder().decode([String].self, from: data) {
            return Set(texts.map(normalize))
        }
        if let flags = try? JSONDecoder().decode([Bool].self, from: data) {
            var set = Set<String>()
            for (i, item) in items.enumerated() where i < flags.count && flags[i] {
                set.insert(normalize(item.text))
            }
            return set
        }
        return []
    }

    /// Per-item completion booleans in the current item order, for the view.
    static func flags(from json: String?, items: [MeetingSummary.ActionItem]) -> [Bool] {
        let completed = completedSet(from: json, items: items)
        return items.map { completed.contains(normalize($0.text)) }
    }

    /// Encode the completed items (those whose flag is true) as text-keyed JSON.
    static func json(items: [MeetingSummary.ActionItem], flags: [Bool]) -> String {
        var completed: [String] = []
        for (i, item) in items.enumerated() where i < flags.count && flags[i] {
            completed.append(normalize(item.text))
        }
        return (try? String(decoding: JSONEncoder().encode(completed.sorted()), as: UTF8.self)) ?? "[]"
    }
}
