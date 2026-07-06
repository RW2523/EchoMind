import Foundation
import SwiftData

@ModelActor
actor SwiftDataChatRepository: ChatRepository {
    func append(_ message: ChatMessageSnapshot) async throws {
        let model = ChatMessage(id: message.id, conversationId: message.conversationId,
                                role: message.role, content: message.content,
                                sourceRefs: message.sourceRefs, createdAt: message.createdAt)
        modelContext.insert(model)
        try modelContext.save()
    }

    func messages(conversationId: UUID) async throws -> [ChatMessageSnapshot] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt)])
        return try modelContext.fetch(descriptor).map {
            ChatMessageSnapshot(id: $0.id, conversationId: $0.conversationId, role: $0.role,
                                content: $0.content, sourceRefs: $0.sourceRefs, createdAt: $0.createdAt)
        }
    }

    func deleteAll() async throws {
        try modelContext.delete(model: ChatMessage.self)
        try modelContext.save()
    }
}
