import Foundation
import FoundationModels

/// Guided update to long-term memory after a report (R3): what to remember, what
/// to forget. Small schema — a handful of short facts.
@Generable
nonisolated struct MemoryUpdate: Sendable {
    @Guide(description: "Durable new facts worth remembering across meetings (people, projects, decisions, preferences, recurring meetings). Empty if nothing new.", .count(0...8))
    var add: [MemoryFactDraft]
    @Guide(description: "Exact texts of previously-known facts that are now outdated and should be forgotten", .count(0...5))
    var retire: [String]

    init(add: [MemoryFactDraft] = [], retire: [String] = []) {
        self.add = add
        self.retire = retire
    }
}

@Generable
nonisolated struct MemoryFactDraft: Sendable {
    @Guide(description: "One of: person, project, decision, preference, recurring, general")
    var kind: String
    @Guide(description: "The fact in one short, self-contained sentence")
    var text: String

    init(kind: String = "general", text: String) {
        self.kind = kind
        self.text = text
    }
}

nonisolated protocol MemoryDistilling: Sendable {
    func distill(reportOverview: String, sessionId: UUID) async
}

/// Turns a fresh report into memory updates and applies them, keeping the store
/// bounded (`maxFacts`, oldest evicted first). Routed through the same gateway as
/// everything else, so it works with the local LLM too.
nonisolated struct MemoryDistiller: MemoryDistilling {
    let gateway: any ModelGateway
    let store: any MemoryStore
    var maxFacts: Int = 60

    private static let instruction = """
    You maintain a compact long-term memory about the user's meetings. Given a new \
    meeting summary and the facts already known, return only durable facts to ADD \
    (people, projects, decisions, preferences, recurring meetings — not one-off \
    trivia) and the exact texts of known facts to RETIRE because they're now \
    outdated. Keep facts short and self-contained. Add nothing if there's nothing \
    durable.
    """

    func distill(reportOverview: String, sessionId: UUID) async {
        let overview = reportOverview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overview.isEmpty else { return }

        let existing = ((try? await store.all()) ?? []).prefix(40)
        let known = existing.map { "- \($0.text)" }.joined(separator: "\n")
        let prompt = """
        New meeting summary:
        \(overview)

        Already known:
        \(known.isEmpty ? "(nothing yet)" : known)
        """

        guard let update = try? await gateway.generate(
            instructions: Self.instruction, prompt: prompt, as: MemoryUpdate.self) else { return }

        try? await store.retire(matching: update.retire)
        let facts = update.add.compactMap { draft -> MemoryFactSnapshot? in
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MemoryFactSnapshot(
                id: UUID(),
                kind: MemoryFactKind(rawValue: draft.kind.lowercased()) ?? .general,
                text: text, sourceSessionId: sessionId, updatedAt: Date())
        }
        try? await store.add(facts)
        try? await store.prune(max: maxFacts)
    }
}

/// Builds a token-bounded "known facts" block for prompt injection (R3). Pure and
/// testable; facts beyond the budget are dropped (memory yields to grounding).
nonisolated enum MemoryPreamble {
    static func build(from facts: [String], budgeter: TokenBudgeter, maxTokens: Int) -> String {
        guard maxTokens > 0 else { return "" }
        var used = 0
        var lines: [String] = []
        for fact in facts {
            let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let line = "- \(trimmed)"
            let tokens = budgeter.tokens(in: line)
            if used + tokens > maxTokens { break }
            lines.append(line)
            used += tokens
        }
        return lines.joined(separator: "\n")
    }
}
