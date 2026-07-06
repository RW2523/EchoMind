import Foundation

nonisolated enum RetrievalOnlyReason: Sendable, Equatable {
    case tierB(String)
    case generationFailed
    case contextOverflow
}

nonisolated enum AskResult: Sendable, Equatable {
    case grounded(answer: String, sources: [SourceRef])
    case notFound
    case retrievalOnly(passages: [RetrievedChunk], reason: RetrievalOnlyReason)
    case emptyIndex
}

nonisolated enum RAGError: Error, Equatable {
    case questionTooLong
}

nonisolated protocol RAGService: Sendable {
    func ask(_ question: String) async throws -> AskResult
}

nonisolated enum RAGPrompts {
    static let notFoundSentence = "I couldn't find this in your saved knowledge."
    static let instructions = """
    Answer the question using ONLY the provided context passages. Preserve names, \
    numbers, and dates exactly. If the context does not contain the answer, reply \
    with exactly this sentence and nothing else: \(notFoundSentence)
    """
    static func prompt(question: String, context: String) -> String {
        "Context:\n\(context)\n\nQuestion: \(question)"
    }
}

/// Retrieve -> budget-pack -> grounded answer / fallback ladder (§6.3, §3 budgets).
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

        let stored = try await chunks.fetchAll()
        guard !stored.isEmpty else { return .emptyIndex }

        // Embed question + retrieve top-K.
        let dimension = try await embedder.dimension
        guard let queryVector = try await embedder.embed([trimmed]).first else {
            return .retrievalOnly(passages: [], reason: .generationFailed)
        }
        let candidates: [(id: UUID, vector: [Float])] = stored.compactMap { chunk in
            guard let vector = try? VectorPacking.unpack(chunk.embedding, expectedDimension: dimension) else { return nil }
            return (chunk.id, vector)
        }
        let byId = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let retrieved: [RetrievedChunk] = search.topK(query: queryVector, candidates: candidates, k: Self.retrieveK)
            .compactMap { hit in byId[hit.id].map { RetrievedChunk(chunk: $0, score: hit.score) } }

        // Tier B → retrieval-only, a first-class result.
        if case .tierB(let reason) = await availability() {
            return .retrievalOnly(passages: retrieved, reason: .tierB(Self.reasonText(reason)))
        }

        let packed = packChunks(retrieved, question: trimmed)
        do {
            return try await answer(question: trimmed, packed: packed)
        } catch ModelGatewayError.exceededContextWindow {
            guard packed.count > 1 else { return .retrievalOnly(passages: retrieved, reason: .contextOverflow) }
            do {
                return try await answer(question: trimmed, packed: Array(packed.dropLast()))
            } catch {
                return .retrievalOnly(passages: retrieved, reason: .contextOverflow)
            }
        } catch {
            return .retrievalOnly(passages: retrieved, reason: .generationFailed)
        }
    }

    // MARK: - Helpers

    private func answer(question: String, packed: [RetrievedChunk]) async throws -> AskResult {
        let context = packed.enumerated()
            .map { "[\($0.offset + 1)] \($0.element.chunk.text)" }
            .joined(separator: "\n\n")
        let response = try await gateway.respond(
            instructions: RAGPrompts.instructions,
            prompt: RAGPrompts.prompt(question: question, context: context),
            maxOutputTokens: Self.outputReserve)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == RAGPrompts.notFoundSentence { return .notFound }
        let sources = packed.map {
            SourceRef(sourceId: $0.chunk.sourceId, sourceType: $0.chunk.sourceType, chunkId: $0.chunk.id)
        }
        return .grounded(answer: trimmed, sources: sources)
    }

    private func packChunks(_ retrieved: [RetrievedChunk], question: String) -> [RetrievedChunk] {
        let overhead = budgeter.tokens(in: RAGPrompts.instructions) + budgeter.tokens(in: question)
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
