import Foundation

/// Persistence for Ask chat history (§6.3).
nonisolated protocol ChatRepository: Sendable {
    func append(_ message: ChatMessageSnapshot) async throws
    func messages(conversationId: UUID) async throws -> [ChatMessageSnapshot]
    func deleteAll() async throws
}
