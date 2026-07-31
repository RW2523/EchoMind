import Testing
import Foundation
@testable import EchoMind

@Suite struct ChatRepositoryTests {
    @Test func sourceRefsSurviveStoreRoundTrip() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataChatRepository(modelContainer: container)
        let conversation = UUID()
        let refs = [SourceRef(sourceId: UUID(), sourceType: .document, chunkId: UUID()),
                    SourceRef(sourceId: UUID(), sourceType: .session, chunkId: UUID())]

        try await repo.append(ChatMessageSnapshot(conversationId: conversation, role: .user, content: "Q?"))
        try await repo.append(ChatMessageSnapshot(conversationId: conversation, role: .assistant,
                                                  content: "A.", sourceRefs: refs))

        // Fresh repository confirms persistence, not caching.
        let reloaded = try await SwiftDataChatRepository(modelContainer: container)
            .messages(conversationId: conversation)
        #expect(reloaded.count == 2)
        #expect(reloaded[0].role == .user)
        #expect(reloaded[1].sourceRefs == refs)
    }

    @Test func deleteMessagesClearsOnlyThatConversation() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataChatRepository(modelContainer: container)
        let ask = UUID()
        let other = UUID()
        try await repo.append(ChatMessageSnapshot(conversationId: ask, role: .user, content: "hi"))
        try await repo.append(ChatMessageSnapshot(conversationId: ask, role: .assistant, content: "hello"))
        try await repo.append(ChatMessageSnapshot(conversationId: other, role: .user, content: "keep me"))

        try await repo.deleteMessages(conversationId: ask)

        #expect(try await repo.messages(conversationId: ask).isEmpty)          // cleared
        #expect(try await repo.messages(conversationId: other).count == 1)     // untouched
    }

    @Test func messagesReturnInChronologicalOrder() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataChatRepository(modelContainer: container)
        let conversation = UUID()
        try await repo.append(ChatMessageSnapshot(conversationId: conversation, role: .user,
                                                  content: "first", createdAt: Date(timeIntervalSince1970: 1)))
        try await repo.append(ChatMessageSnapshot(conversationId: conversation, role: .assistant,
                                                  content: "second", createdAt: Date(timeIntervalSince1970: 2)))
        let messages = try await repo.messages(conversationId: conversation)
        #expect(messages.map(\.content) == ["first", "second"])
    }
}
