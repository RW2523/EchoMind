import Foundation
import SwiftData

/// A durable, cross-session fact EchoMind remembers about the user's meetings (R3).
/// The app's long-term brain — compact enough to inject whole into prompts. Carries
/// provenance (`sourceSessionId`) so the user can see where a fact came from and
/// delete it. Additive model → SwiftData lightweight migration.
@Model
final class MemoryFact {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var text: String
    var sourceSessionId: UUID?
    var updatedAt: Date

    var kind: MemoryFactKind {
        get { MemoryFactKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), kind: MemoryFactKind = .general, text: String,
         sourceSessionId: UUID? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.text = text
        self.sourceSessionId = sourceSessionId
        self.updatedAt = updatedAt
    }

    var snapshot: MemoryFactSnapshot {
        MemoryFactSnapshot(id: id, kind: kind, text: text,
                           sourceSessionId: sourceSessionId, updatedAt: updatedAt)
    }
}

nonisolated enum MemoryFactKind: String, Sendable, Equatable, CaseIterable {
    case person, project, decision, preference, recurring, general

    var symbol: String {
        switch self {
        case .person: return "person.fill"
        case .project: return "folder.fill"
        case .decision: return "checkmark.seal.fill"
        case .preference: return "slider.horizontal.3"
        case .recurring: return "repeat"
        case .general: return "sparkles"
        }
    }
}

nonisolated struct MemoryFactSnapshot: Sendable, Identifiable, Equatable {
    var id: UUID
    var kind: MemoryFactKind
    var text: String
    var sourceSessionId: UUID?
    var updatedAt: Date
}
