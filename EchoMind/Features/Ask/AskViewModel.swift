import Foundation

@MainActor
@Observable
final class AskViewModel {
    enum SendState: Equatable { case idle, thinking }

    private(set) var messages: [AskMessage] = []
    private(set) var state: SendState = .idle
    var draft = ""

    private let rag: any RAGService
    private let chat: any ChatRepository
    private let chunks: any ChunkRepository
    private let documents: any DocumentRepository
    private let sessions: any SessionRepository

    // Single default conversation in V1.
    private let conversationId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!

    init(rag: any RAGService, chat: any ChatRepository, chunks: any ChunkRepository,
         documents: any DocumentRepository, sessions: any SessionRepository) {
        self.rag = rag
        self.chat = chat
        self.chunks = chunks
        self.documents = documents
        self.sessions = sessions
    }

    func load() async {
        let stored = (try? await chat.messages(conversationId: conversationId)) ?? []
        var display: [AskMessage] = []
        for snapshot in stored { display.append(await render(snapshot)) }
        messages = display
    }

    func send() async {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, state == .idle else { return }
        draft = ""

        // Prior turns (before this question) become the pipeline's memory.
        let history = messages.map { ChatTurn(role: $0.role, content: $0.content) }
        let userMessage = ChatMessageSnapshot(conversationId: conversationId, role: .user, content: question)
        try? await chat.append(userMessage)
        messages.append(await render(userMessage))

        state = .thinking
        defer { state = .idle }

        do {
            let result = try await rag.ask(question, history: history)
            messages.append(await persist(result))
        } catch RAGError.questionTooLong {
            await appendAssistant("That question is too long. Try asking something shorter.")
        } catch {
            await appendAssistant("Something went wrong answering that. Please try again.")
        }
    }

    func askFollowUp(_ text: String) async {
        guard state == .idle else { return }
        draft = text
        await send()
    }

    /// Voice entry point (Voice Agent V1): runs the same pipeline for a spoken
    /// `question`, updates the chat thread with bubbles, and returns the answer
    /// text to speak aloud (nil if nothing to say).
    func askVoice(_ question: String) async -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state == .idle else { return nil }

        let history = messages.map { ChatTurn(role: $0.role, content: $0.content) }
        let userMessage = ChatMessageSnapshot(conversationId: conversationId, role: .user, content: trimmed)
        try? await chat.append(userMessage)
        messages.append(await render(userMessage))

        state = .thinking
        defer { state = .idle }

        do {
            let result = try await rag.ask(trimmed, history: history)
            let message = await persist(result)
            messages.append(message)
            return message.content
        } catch RAGError.questionTooLong {
            let text = "That question is too long. Try asking something shorter."
            await appendAssistant(text)
            return text
        } catch {
            let text = "Something went wrong answering that. Please try again."
            await appendAssistant(text)
            return text
        }
    }

    /// The most recent assistant message's suggested follow-ups, if any.
    var suggestedFollowUps: [String] {
        guard state == .idle, let last = messages.last, last.role == .assistant else { return [] }
        return last.followUps
    }

    /// Streaming voice entry point (Voice Agent V2): appends the user bubble, streams
    /// the cumulative answer for TTS, and persists the assistant bubble on completion.
    func askVoiceStream(_ question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, state == .idle else { continuation.finish(); return }

                let history = messages.map { ChatTurn(role: $0.role, content: $0.content) }
                let userMessage = ChatMessageSnapshot(conversationId: conversationId, role: .user, content: trimmed)
                try? await chat.append(userMessage)
                messages.append(await render(userMessage))
                state = .thinking

                var full = ""
                do {
                    if let streaming = rag as? StreamingRAGService {
                        for try await cumulative in streaming.askStreaming(trimmed, history: history) {
                            full = cumulative
                            continuation.yield(cumulative)
                        }
                    } else {
                        full = try await rag.ask(trimmed, history: history).spokenText
                        continuation.yield(full)
                    }
                } catch {
                    full = ""
                }

                var finalText = full.trimmingCharacters(in: .whitespacesAndNewlines)
                if finalText.isEmpty {
                    finalText = "Sorry, I couldn't answer that."
                    continuation.yield(finalText)
                }
                await appendAssistant(finalText)
                continuation.finish()
                state = .idle
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Result handling

    private func persist(_ result: AskResult) async -> AskMessage {
        switch result {
        case .grounded(let answer, let refs, let followUps):
            let message = ChatMessageSnapshot(conversationId: conversationId, role: .assistant,
                                              content: answer, sourceRefs: refs)
            try? await chat.append(message)
            return AskMessage(id: message.id, role: .assistant, content: answer,
                              sources: await resolve(refs), kind: .grounded, followUps: followUps)
        case .conversational(let answer, let followUps):
            let message = ChatMessageSnapshot(conversationId: conversationId, role: .assistant, content: answer)
            try? await chat.append(message)
            return AskMessage(id: message.id, role: .assistant, content: answer, sources: [], kind: .plain,
                              followUps: followUps)
        case .retrievalOnly(let passages, let reason):
            let refs = passages.map { SourceRef(sourceId: $0.chunk.sourceId, sourceType: $0.chunk.sourceType, chunkId: $0.chunk.id) }
            let header = Self.header(for: reason)
            let message = ChatMessageSnapshot(conversationId: conversationId, role: .assistant,
                                              content: header, sourceRefs: refs)
            try? await chat.append(message)
            return AskMessage(id: message.id, role: .assistant, content: header,
                              sources: await resolve(refs), kind: .retrievalOnly)
        }
    }

    private func appendAssistant(_ text: String) async {
        let message = ChatMessageSnapshot(conversationId: conversationId, role: .assistant, content: text)
        try? await chat.append(message)
        messages.append(AskMessage(id: message.id, role: .assistant, content: text, sources: [], kind: .plain))
    }

    // MARK: - Rendering / source resolution

    private func render(_ snapshot: ChatMessageSnapshot) async -> AskMessage {
        let kind: AskMessage.Kind
        if snapshot.role == .user { kind = .user }
        else if snapshot.sourceRefs.isEmpty { kind = .plain }
        else { kind = .grounded }
        return AskMessage(id: snapshot.id, role: snapshot.role, content: snapshot.content,
                          sources: await resolve(snapshot.sourceRefs), kind: kind)
    }

    private func resolve(_ refs: [SourceRef]) async -> [AskSource] {
        guard !refs.isEmpty else { return [] }
        let chunkIds = refs.compactMap(\.chunkId)
        let fetched = (try? await chunks.fetch(ids: chunkIds)) ?? []
        let chunkById = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var sources: [AskSource] = []
        for ref in refs {
            let chunk = ref.chunkId.flatMap { chunkById[$0] }
            let detail = chunk?.pageNumber.map { "Page \($0)" }
                ?? chunk?.timestamp.map { SessionExporter.timestamp($0) }
            sources.append(AskSource(
                id: ref.chunkId ?? ref.sourceId,
                title: await title(ref.sourceId, ref.sourceType),
                detail: detail,
                preview: chunk?.text,
                sourceId: ref.sourceId, sourceType: ref.sourceType,
                pageNumber: chunk?.pageNumber, timestamp: chunk?.timestamp))
        }
        return sources
    }

    private func title(_ id: UUID, _ type: SourceType) async -> String {
        switch type {
        case .document: return (try? await documents.fetchDocument(id: id))?.title ?? "Document"
        case .session: return (try? await sessions.fetchSession(id: id))?.title ?? "Session"
        }
    }

    static func header(for reason: RetrievalOnlyReason) -> String {
        switch reason {
        case .tierB(let text): return "Here's what I found in your knowledge. \(text)"
        case .generationFailed, .contextOverflow: return "Here's what I found in your knowledge."
        }
    }
}
