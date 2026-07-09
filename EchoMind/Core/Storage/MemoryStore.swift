import Foundation
import SwiftData

/// Persistence for the long-term memory facts (R3). Off the main actor via
/// `@ModelActor`; callers exchange Sendable snapshots.
nonisolated protocol MemoryStore: Sendable {
    /// Newest-first.
    func all() async throws -> [MemoryFactSnapshot]
    func add(_ facts: [MemoryFactSnapshot]) async throws
    /// Delete facts whose text matches (case-insensitive) any of `texts`.
    func retire(matching texts: [String]) async throws
    func delete(id: UUID) async throws
    func count() async throws -> Int
    func deleteAll() async throws
    /// Keep only the `max` most recently updated facts (byte-budget eviction).
    func prune(max: Int) async throws
}

@ModelActor
actor SwiftDataMemoryStore: MemoryStore {
    func all() async throws -> [MemoryFactSnapshot] {
        let descriptor = FetchDescriptor<MemoryFact>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.snapshot)
    }

    func add(_ facts: [MemoryFactSnapshot]) async throws {
        guard !facts.isEmpty else { return }
        // Dedup by normalized text — against what's already stored AND within this batch.
        // The distiller re-derives the same durable facts across meetings; without this,
        // duplicates accumulate and eviction (prune) pushes out genuinely distinct facts.
        let existing = try modelContext.fetch(FetchDescriptor<MemoryFact>())
        var seen = [String: MemoryFact]()
        for fact in existing where seen[Self.normalize(fact.text)] == nil {
            seen[Self.normalize(fact.text)] = fact
        }
        for fact in facts {
            let key = Self.normalize(fact.text)
            guard !key.isEmpty else { continue }
            if let match = seen[key] {
                // Same fact seen again — refresh recency so it survives pruning, no dupe.
                match.updatedAt = max(match.updatedAt, fact.updatedAt)
            } else {
                let model = MemoryFact(id: fact.id, kind: fact.kind, text: fact.text,
                                       sourceSessionId: fact.sourceSessionId, updatedAt: fact.updatedAt)
                modelContext.insert(model)
                seen[key] = model
            }
        }
        try modelContext.save()
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func retire(matching texts: [String]) async throws {
        guard !texts.isEmpty else { return }
        let targets = Set(texts.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        for fact in try modelContext.fetch(FetchDescriptor<MemoryFact>())
        where targets.contains(fact.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            modelContext.delete(fact)
        }
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        var descriptor = FetchDescriptor<MemoryFact>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let fact = try modelContext.fetch(descriptor).first {
            modelContext.delete(fact)
            try modelContext.save()
        }
    }

    func count() async throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<MemoryFact>())
    }

    func deleteAll() async throws {
        for fact in try modelContext.fetch(FetchDescriptor<MemoryFact>()) { modelContext.delete(fact) }
        try modelContext.save()
    }

    func prune(max: Int) async throws {
        let all = try modelContext.fetch(
            FetchDescriptor<MemoryFact>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        guard all.count > max else { return }
        for fact in all[max...] { modelContext.delete(fact) }
        try modelContext.save()
    }
}
