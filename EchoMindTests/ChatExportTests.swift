import Testing
import Foundation
@testable import EchoMind

/// Chat → .txt export: role labels, order, sources line, and the file name.
@Suite struct ChatExportTests {
    private func msg(_ role: MessageRole, _ content: String,
                     sources: [AskSource] = []) -> AskMessage {
        AskMessage(id: UUID(), role: role, content: content, sources: sources,
                   kind: role == .user ? .user : .grounded)
    }

    private func source(_ title: String, detail: String? = nil) -> AskSource {
        AskSource(id: UUID(), title: title, detail: detail, preview: nil,
                  sourceId: UUID(), sourceType: .session, pageNumber: nil, timestamp: nil)
    }

    @Test func rolesAndOrderArePreserved() {
        let text = ChatExport.text(messages: [
            msg(.user, "What did we decide?"),
            msg(.assistant, "You decided to ship Friday."),
            msg(.user, "Who owns it?"),
        ], exportedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let youIdx = text.range(of: "You:\nWhat did we decide?")
        let botIdx = text.range(of: "EchoMind:\nYou decided to ship Friday.")
        let secondYou = text.range(of: "You:\nWho owns it?")
        #expect(youIdx != nil && botIdx != nil && secondYou != nil)
        #expect(youIdx!.lowerBound < botIdx!.lowerBound)
        #expect(botIdx!.lowerBound < secondYou!.lowerBound)
        #expect(text.hasPrefix(ChatExport.header))
    }

    @Test func sourcesLineListsTitlesWithDetail() {
        let text = ChatExport.text(messages: [
            msg(.assistant, "Grounded answer.",
                sources: [source("Q3 Planning", detail: "02:15"), source("Handbook")]),
        ])
        #expect(text.contains("[Sources: Q3 Planning (02:15); Handbook]"))
    }

    @Test func messagesWithoutSourcesHaveNoSourcesLine() {
        let text = ChatExport.text(messages: [msg(.assistant, "Just chat.")])
        #expect(!text.contains("[Sources:"))
    }

    @Test func fileNameIsDateStamped() {
        let name = ChatExport.fileName(for: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(name.hasPrefix("EchoMind-Chat-2023-11-1"))   // TZ-tolerant (14th/15th)
        #expect(name.hasSuffix(".txt"))
    }
}
