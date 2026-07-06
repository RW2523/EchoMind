import Foundation
import SwiftData

/// One turn in the Ask feature (Phase 8). `sourceRefs` are JSON-encoded into
/// `sourceRefsData` behind a computed property — deterministic bytes,
/// migration-safe, and never queried into.
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var roleRaw: String
    var content: String
    var sourceRefsData: Data
    var createdAt: Date

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    var sourceRefs: [SourceRef] {
        get { (try? JSONDecoder().decode([SourceRef].self, from: sourceRefsData)) ?? [] }
        set { sourceRefsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(id: UUID = UUID(), conversationId: UUID, role: MessageRole, content: String,
         sourceRefs: [SourceRef] = [], createdAt: Date = Date()) {
        self.id = id
        self.conversationId = conversationId
        self.roleRaw = role.rawValue
        self.content = content
        self.sourceRefsData = (try? JSONEncoder().encode(sourceRefs)) ?? Data()
        self.createdAt = createdAt
    }
}
