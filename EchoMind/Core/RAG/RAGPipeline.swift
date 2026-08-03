import Foundation

nonisolated enum RetrievalOnlyReason: Sendable, Equatable {
    case tierB(String)
    case generationFailed
    case contextOverflow
}

nonisolated enum AskResult: Sendable, Equatable {
    case grounded(answer: String, sources: [SourceRef], followUps: [String])
    case conversational(answer: String, followUps: [String])
    case retrievalOnly(passages: [RetrievedChunk], reason: RetrievalOnlyReason)
}

nonisolated enum RAGError: Error, Equatable {
    case questionTooLong
}

nonisolated protocol RAGService: Sendable {
    /// `history` is prior turns (oldest→newest) for multi-turn memory.
    func ask(_ question: String, history: [ChatTurn]) async throws -> AskResult
}

/// Optional streaming capability for the voice agent (V2). Yields the cumulative
/// spoken answer as it generates, so TTS can start on sentence one. Checked with
/// `as? StreamingRAGService`, so `RAGService` stays unchanged for other callers.
nonisolated protocol StreamingRAGService: Sendable {
    func askStreaming(_ question: String, history: [ChatTurn]) -> AsyncThrowingStream<String, Error>
}

extension AskResult {
    /// Plain text to speak / show for any result kind.
    var spokenText: String {
        switch self {
        case .grounded(let answer, _, _): return answer
        case .conversational(let answer, _): return answer
        case .retrievalOnly: return "Here's what I found in your knowledge."
        }
    }
}

nonisolated enum RAGPrompts {
    static let hybrid = """
    You are EchoMind, a friendly, concise assistant. Below is the conversation so \
    far and numbered Context passages [1], [2], … from the user's own saved \
    knowledge (which may be empty). If the Context is relevant to the latest \
    message, answer using it, set usedProvidedContext to true, preserve names, \
    numbers, and dates verbatim, and list the passage numbers you used in \
    citedPassages. Only cite passages that directly support your answer. \
    Otherwise answer naturally, set usedProvidedContext to false, and leave \
    citedPassages empty. Always suggest two or three short follow-up questions.
    """

    static let rewrite = """
    Rewrite the user's latest message into a single standalone search query using \
    the conversation for context (resolve pronouns like "it" or "they"). Output ONLY \
    the query text, nothing else.
    """

    /// Adaptive multi-query expansion (used only when the first retrieval pass is
    /// weak): alternative phrasings widen recall over the user's own wording.
    static let expand = """
    Rewrite the search query two different ways — use synonyms and related phrasing \
    someone might have used when speaking. Output ONLY the two rewrites, one per \
    line, nothing else.
    """

    /// Voice answers are spoken aloud: concise plain prose, no markdown, no lists,
    /// no citations — one or two short paragraphs at most.
    static let voiceProse = """
    You are EchoMind, a warm, concise voice assistant. Answer the latest message in \
    natural spoken prose — no markdown, bullet points, or headings. Use the Context \
    if it's relevant, preserving names, numbers, and dates exactly; otherwise answer \
    from general knowledge. Keep it brief and easy to listen to.
    """

    static func prompt(memory: String, question: String, context: String, knownFacts: String = "") -> String {
        var parts: [String] = []
        if !knownFacts.isEmpty { parts.append("Known about the user (from past meetings):\n\(knownFacts)") }
        if !memory.isEmpty { parts.append("Conversation so far:\n\(memory)") }
        parts.append("Context:\n\(context.isEmpty ? "(no saved knowledge is relevant)" : context)")
        parts.append("Latest message: \(question)")
        return parts.joined(separator: "\n\n")
    }
}

/// Conversational, hybrid-retrieval RAG (V2 §A). Multi-turn memory + follow-up
/// query rewrite + vector∪BM25 (RRF) retrieval + one guided call returning the
/// answer, a grounded flag, and follow-up suggestions.
nonisolated struct RAGPipeline: RAGService {
    let retriever: HybridRetriever
    let gateway: any ModelGateway
    let budgeter: TokenBudgeter
    let availability: @Sendable () async -> AvailabilityStatus
    /// R3: recent long-term memory facts (newest first), injected as a bounded
    /// preamble so answers carry context from all prior meetings.
    var knownFacts: (@Sendable () async -> [String])?

    static let totalInputBudget = 2_800
    static let chunkBudget = 2_300
    static let questionTokenLimit = 250
    static let outputReserve = 1_000
    static let retrieveK = 6
    static let memoryTurns = 6
    static let factsBudget = 300

    /// Composes the retrieval engine over the cached corpus, with adaptive
    /// query expansion routed through the same model gateway.
    init(corpus: CorpusCache, embedder: any EmbeddingService, search: VectorSearch,
         gateway: any ModelGateway, budgeter: TokenBudgeter,
         availability: @escaping @Sendable () async -> AvailabilityStatus,
         knownFacts: (@Sendable () async -> [String])? = nil) {
        self.retriever = HybridRetriever(
            corpus: corpus, embedder: embedder, search: search,
            expand: { query in await Self.expandQueries(gateway: gateway, query: query) })
        self.gateway = gateway
        self.budgeter = budgeter
        self.availability = availability
        self.knownFacts = knownFacts
    }

    /// Everything both answer paths need from one retrieval pass.
    struct Retrieval: Sendable {
        let retrieved: [RetrievedChunk]
        let packed: [RetrievedChunk]
        let memory: String
        let context: String
    }

    /// Shared by `ask` and `askStreaming` (previously duplicated): rewrite →
    /// hybrid retrieve (cached corpus, adaptive expansion) → budget-pack →
    /// numbered context block.
    /// Whether the question needs conversation history to make sense as a search
    /// query. Standalone questions skip the rewrite — a full model round-trip that
    /// dominated voice-turn latency (especially on local models).
    static func needsRewrite(_ question: String) -> Bool {
        let tokens = BM25.tokenize(question)
        if tokens.count < 4 { return true }   // "why?", "and pricing?" — needs context
        let contextual: Set<String> = ["it", "that", "this", "they", "them", "he", "she",
                                       "him", "her", "his", "hers", "their", "those", "these", "one"]
        return !contextual.isDisjoint(with: Set(tokens))
    }

    func retrieveContext(question: String, history: [ChatTurn]) async throws -> Retrieval {
        let searchQuery = (history.isEmpty || !Self.needsRewrite(question))
            ? question
            : await rewrite(question, history: history)
        let retrieved = try await retriever.retrieve(searchQuery, k: Self.retrieveK)
        let memory = Self.memory(from: history)
        let packed = packChunks(retrieved, question: question, memory: memory)
        let context = packed.enumerated()
            .map { "[\($0.offset + 1)] \($0.element.chunk.text)" }
            .joined(separator: "\n\n")
        return Retrieval(retrieved: retrieved, packed: packed, memory: memory, context: context)
    }

    func ask(_ question: String, history: [ChatTurn]) async throws -> AskResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard budgeter.tokens(in: trimmed) <= Self.questionTokenLimit else { throw RAGError.questionTooLong }

        let status = await availability()
        let retrieval = try await retrieveContext(question: trimmed, history: history)

        // Tier B: no generation — return passages honestly.
        if case .tierB(let reason) = status {
            return .retrievalOnly(passages: retrieval.retrieved, reason: .tierB(Self.reasonText(reason)))
        }

        // One unified guided call — grounds (with citations) if the context is
        // relevant, chats otherwise; always returns follow-ups.
        let facts = await factsBlock()
        do {
            return try await answer(question: trimmed, retrieval: retrieval, facts: facts,
                                    packed: retrieval.packed)
        } catch ModelGatewayError.exceededContextWindow {
            guard retrieval.packed.count > 1 else {
                return .retrievalOnly(passages: retrieval.retrieved, reason: .contextOverflow)
            }
            do {
                return try await answer(question: trimmed, retrieval: retrieval, facts: facts,
                                        packed: Array(retrieval.packed.dropLast()))
            } catch {
                return .retrievalOnly(passages: retrieval.retrieved, reason: .contextOverflow)
            }
        } catch {
            return .retrievalOnly(passages: retrieval.retrieved, reason: .generationFailed)
        }
    }

    /// R3: bounded "known facts" block from long-term memory, or "" when none.
    private func factsBlock() async -> String {
        guard let knownFacts else { return "" }
        return MemoryPreamble.build(from: await knownFacts(), budgeter: budgeter, maxTokens: Self.factsBudget)
    }

    // MARK: - Generation

    private func answer(question: String, retrieval: Retrieval, facts: String,
                        packed: [RetrievedChunk]) async throws -> AskResult {
        let context = packed.enumerated()
            .map { "[\($0.offset + 1)] \($0.element.chunk.text)" }
            .joined(separator: "\n\n")
        let result = try await gateway.generate(
            instructions: RAGPrompts.hybrid,
            prompt: RAGPrompts.prompt(memory: retrieval.memory, question: question,
                                      context: context, knownFacts: facts),
            as: RAGAnswer.self,
            maxOutputTokens: Self.outputReserve)
        let text = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let followUps = Array(result.followUps.prefix(3))
        if result.usedProvidedContext && !packed.isEmpty {
            return .grounded(answer: text,
                             sources: Self.citedSources(result.citedPassages, packed: packed),
                             followUps: followUps)
        }
        return .conversational(answer: text, followUps: followUps)
    }

    /// Map the model's cited passage numbers (1-based) to the exact chunks behind
    /// them — RAGFlow-style precision: sources ARE the passages that back the
    /// answer, in citation order. Invalid/duplicate numbers are dropped; if the
    /// model cited nothing usable, fall back to every packed passage so a grounded
    /// answer never ships without sources.
    static func citedSources(_ cited: [Int], packed: [RetrievedChunk]) -> [SourceRef] {
        var seen = Set<Int>()
        let valid = cited.filter { $0 >= 1 && $0 <= packed.count && seen.insert($0).inserted }
        let indices = valid.isEmpty ? Array(1...packed.count) : valid
        return indices.map { index in
            let chunk = packed[index - 1].chunk
            return SourceRef(sourceId: chunk.sourceId, sourceType: chunk.sourceType, chunkId: chunk.id)
        }
    }

    /// Adaptive expansion (weak retrieval only): two alternative phrasings from
    /// the model, parsed line-by-line. Failure → no expansion, never an error.
    static func expandQueries(gateway: any ModelGateway, query: String) async -> [String] {
        let raw = try? await gateway.respond(
            instructions: RAGPrompts.expand,
            prompt: query,
            maxOutputTokens: 60)
        guard let raw else { return [] }
        return raw.split(separator: "\n")
            .map { line -> String in
                var text = line.trimmingCharacters(in: .whitespaces)
                // Strip list markers the model may add: "1. ", "2) ", "- ", "• "
                while let first = text.first,
                      first.isNumber || first == "." || first == ")" || first == "-" || first == "•" || first == " " {
                    text.removeFirst()
                }
                return text.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    private func rewrite(_ question: String, history: [ChatTurn]) async -> String {
        let memory = Self.memory(from: history)
        let prompt = "Conversation:\n\(memory)\n\nLatest message: \(question)"
        let rewritten = try? await gateway.respond(instructions: RAGPrompts.rewrite, prompt: prompt, maxOutputTokens: 60)
        let cleaned = rewritten?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? question : cleaned
    }

    // MARK: - Budget + memory

    private func packChunks(_ retrieved: [RetrievedChunk], question: String, memory: String) -> [RetrievedChunk] {
        let overhead = budgeter.tokens(in: RAGPrompts.hybrid) + budgeter.tokens(in: question) + budgeter.tokens(in: memory)
        let budget = min(Self.chunkBudget, Self.totalInputBudget - overhead)
        var included: [RetrievedChunk] = []
        var used = 0
        for chunk in retrieved {
            let tokens = budgeter.tokens(in: chunk.chunk.text)
            if used + tokens > budget { break }
            included.append(chunk)
            used += tokens
        }
        if included.isEmpty, let first = retrieved.first { included = [first] }
        return included
    }

    static func memory(from history: [ChatTurn]) -> String {
        history.suffix(memoryTurns).map { turn in
            "\(turn.role == .user ? "User" : "Assistant"): \(turn.content)"
        }.joined(separator: "\n")
    }

    static func reasonText(_ reason: AvailabilityStatus.TierBReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "This iPhone doesn't support Apple Intelligence. Download an on-device model (Settings ▸ AI Models) to enable AI answers."
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence in iOS Settings — or download an on-device model (Settings ▸ AI Models)."
        case .modelNotReady: return "The on-device model is preparing."
        case .unknown: return "AI answers aren't available right now."
        }
    }
}

extension RAGPipeline: StreamingRAGService {
    /// Streams a spoken-prose answer (V2). Same retrieval as `ask`, but emits the
    /// answer token-by-token via the gateway's streaming capability (one-shot
    /// fallback for non-streaming backends). No follow-ups/citations — voice output.
    func askStreaming(_ question: String, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard budgeter.tokens(in: trimmed) <= Self.questionTokenLimit else {
                        throw RAGError.questionTooLong
                    }
                    // Tier B: no generator — fall back to the one-shot result text.
                    if case .tierB = await availability() {
                        continuation.yield(try await ask(trimmed, history: history).spokenText)
                        continuation.finish()
                        return
                    }
                    // Same retrieval as ask() — one shared implementation.
                    let retrieval = try await retrieveContext(question: trimmed, history: history)
                    let facts = await factsBlock()
                    let prompt = RAGPrompts.prompt(memory: retrieval.memory, question: trimmed,
                                                   context: retrieval.context, knownFacts: facts)

                    let source = (gateway as? StreamingModelGateway)?
                        .stream(instructions: RAGPrompts.voiceProse, prompt: prompt, maxOutputTokens: Self.outputReserve)
                        ?? gateway.oneShotStream(instructions: RAGPrompts.voiceProse, prompt: prompt, maxOutputTokens: Self.outputReserve)
                    for try await chunk in source { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
