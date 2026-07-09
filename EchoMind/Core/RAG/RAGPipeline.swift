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
    far and Context passages from the user's own saved knowledge (which may be \
    empty). If the Context is relevant to the latest message, answer using it and \
    set usedProvidedContext to true, preserving names, numbers, and dates verbatim. \
    Otherwise answer naturally and set usedProvidedContext to false. Always suggest \
    two or three short follow-up questions.
    """

    static let rewrite = """
    Rewrite the user's latest message into a single standalone search query using \
    the conversation for context (resolve pronouns like "it" or "they"). Output ONLY \
    the query text, nothing else.
    """

    /// Voice answers are spoken aloud: concise plain prose, no markdown, no lists,
    /// no citations — one or two short paragraphs at most.
    static let voiceProse = """
    You are EchoMind, a warm, concise voice assistant. Answer the latest message in \
    natural spoken prose — no markdown, bullet points, or headings. Use the Context \
    if it's relevant, preserving names, numbers, and dates exactly; otherwise answer \
    from general knowledge. Keep it brief and easy to listen to.
    """

    static func prompt(memory: String, question: String, context: String) -> String {
        var parts: [String] = []
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
    let chunks: any ChunkRepository
    let embedder: any EmbeddingService
    let search: VectorSearch
    let gateway: any ModelGateway
    let budgeter: TokenBudgeter
    let availability: @Sendable () async -> AvailabilityStatus

    static let totalInputBudget = 2_800
    static let chunkBudget = 2_300
    static let questionTokenLimit = 250
    static let outputReserve = 1_000
    static let retrieveK = 6
    static let fusionPoolK = 20
    static let mmrPoolK = 12
    static let mmrLambda: Float = 0.7
    static let memoryTurns = 6

    func ask(_ question: String, history: [ChatTurn]) async throws -> AskResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard budgeter.tokens(in: trimmed) <= Self.questionTokenLimit else { throw RAGError.questionTooLong }

        let status = await availability()
        let stored = try await chunks.fetchAll()
        let searchQuery = history.isEmpty ? trimmed : await rewrite(trimmed, history: history)

        // Tier B: no generation — return passages honestly.
        if case .tierB(let reason) = status {
            let retrieved = stored.isEmpty ? [] : try await hybridRetrieve(searchQuery, from: stored)
            return .retrievalOnly(passages: retrieved, reason: .tierB(Self.reasonText(reason)))
        }

        // Tier A: one unified guided call — grounds if the context is relevant,
        // chats otherwise; always returns follow-ups.
        let retrieved = stored.isEmpty ? [] : try await hybridRetrieve(searchQuery, from: stored)
        let memory = Self.memory(from: history)
        let packed = packChunks(retrieved, question: trimmed, memory: memory)
        do {
            return try await answer(question: trimmed, memory: memory, packed: packed)
        } catch ModelGatewayError.exceededContextWindow {
            guard packed.count > 1 else { return .retrievalOnly(passages: retrieved, reason: .contextOverflow) }
            do {
                return try await answer(question: trimmed, memory: memory, packed: Array(packed.dropLast()))
            } catch {
                return .retrievalOnly(passages: retrieved, reason: .contextOverflow)
            }
        } catch {
            return .retrievalOnly(passages: retrieved, reason: .generationFailed)
        }
    }

    // MARK: - Generation

    private func answer(question: String, memory: String, packed: [RetrievedChunk]) async throws -> AskResult {
        let context = packed.enumerated()
            .map { "[\($0.offset + 1)] \($0.element.chunk.text)" }
            .joined(separator: "\n\n")
        let result = try await gateway.generate(
            instructions: RAGPrompts.hybrid,
            prompt: RAGPrompts.prompt(memory: memory, question: question, context: context),
            as: RAGAnswer.self)
        let text = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let followUps = Array(result.followUps.prefix(3))
        if result.usedProvidedContext && !packed.isEmpty {
            let sources = packed.map {
                SourceRef(sourceId: $0.chunk.sourceId, sourceType: $0.chunk.sourceType, chunkId: $0.chunk.id)
            }
            return .grounded(answer: text, sources: sources, followUps: followUps)
        }
        return .conversational(answer: text, followUps: followUps)
    }

    private func rewrite(_ question: String, history: [ChatTurn]) async -> String {
        let memory = Self.memory(from: history)
        let prompt = "Conversation:\n\(memory)\n\nLatest message: \(question)"
        let rewritten = try? await gateway.respond(instructions: RAGPrompts.rewrite, prompt: prompt, maxOutputTokens: 60)
        let cleaned = rewritten?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? question : cleaned
    }

    // MARK: - Hybrid retrieval

    private func hybridRetrieve(_ query: String, from stored: [ChunkSnapshot]) async throws -> [RetrievedChunk] {
        let dimension = try await embedder.dimension
        guard let queryVector = try await embedder.embed([query]).first else { return [] }

        let vectorCandidates: [(id: UUID, vector: [Float])] = stored.compactMap { chunk in
            guard let vector = try? VectorPacking.unpack(chunk.embedding, expectedDimension: dimension) else { return nil }
            return (chunk.id, vector)
        }
        let vectorRanking = search.topK(query: queryVector, candidates: vectorCandidates, k: Self.fusionPoolK).map(\.id)
        let bm25Ranking = BM25().rank(query: query, documents: stored.map { (id: $0.id, text: $0.text) },
                                      k: Self.fusionPoolK).map(\.id)

        let byId = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let fused = BM25.reciprocalRankFusion([vectorRanking, bm25Ranking])
        let ordered = mmrOrder(fused: fused, queryVector: queryVector, vectors: vectorCandidates)
        let scoreById = Dictionary(fused.map { ($0.id, $0.score) }, uniquingKeysWith: { first, _ in first })
        return ordered.compactMap { id in
            byId[id].map { RetrievedChunk(chunk: $0, score: Float(scoreById[id] ?? 0)) }
        }
    }

    /// MMR-rerank the fused pool for diversity, then take `retrieveK`. Fused
    /// candidates that came from BM25 only (no usable vector) are appended in fused
    /// order so exact keyword hits are never dropped by the diversity pass.
    private func mmrOrder(fused: [(id: UUID, score: Double)],
                          queryVector: [Float],
                          vectors: [(id: UUID, vector: [Float])]) -> [UUID] {
        let pool = Array(fused.prefix(Self.mmrPoolK))
        let vecById = Dictionary(vectors.map { ($0.id, $0.vector) }, uniquingKeysWith: { first, _ in first })
        let mmrInput = pool.compactMap { item in vecById[item.id].map { (id: item.id, vector: $0) } }
        guard mmrInput.count >= 2 else { return pool.prefix(Self.retrieveK).map(\.id) }

        var picked = MMRReranker(lambda: Self.mmrLambda)
            .rerank(query: queryVector, candidates: mmrInput, k: Self.retrieveK)
        var seen = Set(picked)
        for item in pool where !seen.contains(item.id) {
            guard picked.count < Self.retrieveK else { break }
            picked.append(item.id)
            seen.insert(item.id)
        }
        return picked
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
        case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: return "Enable Apple Intelligence in iOS Settings for AI answers."
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
                    let stored = try await chunks.fetchAll()
                    let searchQuery = history.isEmpty ? trimmed : await rewrite(trimmed, history: history)
                    let retrieved = stored.isEmpty ? [] : try await hybridRetrieve(searchQuery, from: stored)
                    let memory = Self.memory(from: history)
                    let packed = packChunks(retrieved, question: trimmed, memory: memory)
                    let context = packed.enumerated()
                        .map { "[\($0.offset + 1)] \($0.element.chunk.text)" }
                        .joined(separator: "\n\n")
                    let prompt = RAGPrompts.prompt(memory: memory, question: trimmed, context: context)

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
