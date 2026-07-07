import Foundation

nonisolated enum RetrievalOnlyReason: Sendable, Equatable {
    case tierB(String)
    case generationFailed
    case contextOverflow
}

nonisolated enum AskResult: Sendable, Equatable {
    /// Answered from the user's knowledge; sources cite the passages used.
    case grounded(answer: String, sources: [SourceRef])
    /// Casual chat / general knowledge — no sources.
    case conversational(answer: String)
    /// Tier B or a generation failure — the top passages, no generated answer.
    case retrievalOnly(passages: [RetrievedChunk], reason: RetrievalOnlyReason)
}

nonisolated enum RAGError: Error, Equatable {
    case questionTooLong
}

nonisolated protocol RAGService: Sendable {
    func ask(_ question: String) async throws -> AskResult
}

nonisolated enum RAGPrompts {
    /// Used when there is knowledge to consult — the model decides whether it's relevant.
    static let hybrid = """
    You are EchoMind, a friendly and helpful assistant. The user may chat casually \
    or ask about their own saved knowledge, which is provided below as Context \
    passages. If the Context is relevant to the message, answer using it and set \
    usedProvidedContext to true, preserving names, numbers, and dates verbatim. If \
    the message is casual conversation or general knowledge unrelated to the Context, \
    answer naturally and set usedProvidedContext to false. Keep answers concise.
    """

    /// Used when there is no knowledge indexed yet — pure conversation.
    static let conversational = """
    You are EchoMind, a friendly and concise assistant. Respond helpfully to the \
    user's message. If they ask about their saved notes or documents, let them know \
    they can add knowledge by importing a document or recording a session.
    """

    static func prompt(question: String, context: String) -> String {
        "Context:\n\(context)\n\nMessage: \(question)"
    }
}

/// Hybrid chatbot: conversational for chit-chat, grounded for knowledge questions.
/// The model itself flags whether it used the retrieved context (§3 budgets hold).
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

    func ask(_ question: String) async throws -> AskResult {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard budgeter.tokens(in: trimmed) <= Self.questionTokenLimit else { throw RAGError.questionTooLong }

        let status = await availability()
        let stored = try await chunks.fetchAll()

        // Tier B: no on-device generation — return passages (or nothing) honestly.
        if case .tierB(let reason) = status {
            let retrieved = stored.isEmpty ? [] : try await retrieve(trimmed, from: stored)
            return .retrievalOnly(passages: retrieved, reason: .tierB(Self.reasonText(reason)))
        }

        // Tier A, empty knowledge → pure conversation.
        if stored.isEmpty {
            do {
                let answer = try await gateway.respond(instructions: RAGPrompts.conversational,
                                                       prompt: trimmed, maxOutputTokens: Self.outputReserve)
                return .conversational(answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                return .retrievalOnly(passages: [], reason: .generationFailed)
            }
        }

        // Tier A with knowledge → retrieve + let the model decide grounded vs chat.
        let retrieved = try await retrieve(trimmed, from: stored)
        let packed = packChunks(retrieved, question: trimmed)
        do {
            return try await hybridAnswer(question: trimmed, packed: packed)
        } catch ModelGatewayError.exceededContextWindow {
            guard packed.count > 1 else { return .retrievalOnly(passages: retrieved, reason: .contextOverflow) }
            do {
                return try await hybridAnswer(question: trimmed, packed: Array(packed.dropLast()))
            } catch {
                return .retrievalOnly(passages: retrieved, reason: .contextOverflow)
            }
        } catch {
            return .retrievalOnly(passages: retrieved, reason: .generationFailed)
        }
    }

    // MARK: - Helpers

    private func retrieve(_ question: String, from stored: [ChunkSnapshot]) async throws -> [RetrievedChunk] {
        let dimension = try await embedder.dimension
        guard let queryVector = try await embedder.embed([question]).first else { return [] }
        let candidates: [(id: UUID, vector: [Float])] = stored.compactMap { chunk in
            guard let vector = try? VectorPacking.unpack(chunk.embedding, expectedDimension: dimension) else { return nil }
            return (chunk.id, vector)
        }
        let byId = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return search.topK(query: queryVector, candidates: candidates, k: Self.retrieveK)
            .compactMap { hit in byId[hit.id].map { RetrievedChunk(chunk: $0, score: hit.score) } }
    }

    private func hybridAnswer(question: String, packed: [RetrievedChunk]) async throws -> AskResult {
        let context = packed.enumerated()
            .map { "[\($0.offset + 1)] \($0.element.chunk.text)" }
            .joined(separator: "\n\n")
        let result = try await gateway.generate(
            instructions: RAGPrompts.hybrid,
            prompt: RAGPrompts.prompt(question: question, context: context),
            as: RAGAnswer.self)
        let answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.usedProvidedContext {
            let sources = packed.map {
                SourceRef(sourceId: $0.chunk.sourceId, sourceType: $0.chunk.sourceType, chunkId: $0.chunk.id)
            }
            return .grounded(answer: answer, sources: sources)
        }
        return .conversational(answer: answer)
    }

    private func packChunks(_ retrieved: [RetrievedChunk], question: String) -> [RetrievedChunk] {
        let overhead = budgeter.tokens(in: RAGPrompts.hybrid) + budgeter.tokens(in: question)
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

    static func reasonText(_ reason: AvailabilityStatus.TierBReason) -> String {
        switch reason {
        case .deviceNotEligible: return "This iPhone doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled: return "Enable Apple Intelligence in iOS Settings for AI answers."
        case .modelNotReady: return "The on-device model is preparing."
        case .unknown: return "AI answers aren't available right now."
        }
    }
}
