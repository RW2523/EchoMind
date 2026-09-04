import Testing
import Foundation
import SwiftData
@testable import EchoMind

// Fixes for the college field report: fabricated numbers, missing not-found
// path, cross-document attribution, history echo. Each failure pattern is
// pinned here.

@Suite struct AnswerVerifierTests {
    @Test func extractsAndCanonicalizesNumbers() {
        let numbers = AnswerVerifier.numbers(in: "5,800 clips (5 seconds at 30fps), score 9.5, v2")
        #expect(numbers.contains("5800"))
        #expect(numbers.contains("5"))
        #expect(numbers.contains("30"))
        #expect(numbers.contains("9.5"))
        #expect(numbers.contains("2"))
    }

    @Test func fieldBugNumbersAreFlaggedAsUnsupported() {
        // The exact failure: "22,000 frames split 9,000 each" against a document
        // saying 22 locations, 5,800 clips split 5,000/400/400.
        let context = "Footage from 22 parking locations. 5,800 clips: 5,000 training, 400 validation, 400 test."
        let bad = AnswerVerifier.unsupportedNumbers(
            answer: "The dataset has 22,000 frames split 9,000 each.",
            context: context, question: "how is the dataset split?")
        #expect(bad == ["22000", "9000"])
        let good = AnswerVerifier.unsupportedNumbers(
            answer: "5,800 clips split into 5,000 training, 400 validation and 400 test.",
            context: context, question: "how is the dataset split?")
        #expect(good.isEmpty)
    }

    @Test func questionNumbersAreAllowed() {
        // Echoing a figure the USER stated isn't fabrication.
        let bad = AnswerVerifier.unsupportedNumbers(
            answer: "No, it isn't 300 — the document doesn't give a count.",
            context: "The dataset exists.", question: "is the dataset 300 clips?")
        #expect(bad.isEmpty)
    }

    @Test func numberFormatVariantsMatch() {
        let context = "The split is 5,800 total."
        #expect(AnswerVerifier.unsupportedNumbers(answer: "There are 5800 total.",
                                                  context: context, question: "").isEmpty)
    }

    @Test func zeroPaddingAndTrailingZerosCanonicalize() {
        // "09:00" restated as "9", "5.50" as "5.5" — same values, no false flag.
        #expect(AnswerVerifier.unsupportedNumbers(answer: "The meeting is at 9, cost 5.5 dollars.",
                                                  context: "Meeting at 09:00, price $5.50.", question: "").isEmpty)
        // "0.5" must survive (not become "5" or ".5").
        #expect(AnswerVerifier.numbers(in: "0.5 ratio") == ["0.5"])
        #expect(AnswerVerifier.numbers(in: "007 agent") == ["7"])
    }

    @Test func extraAllowedSourcesSupportFigures() {
        // Known-facts block and earlier USER turns are legitimate support.
        let bad = AnswerVerifier.unsupportedNumbers(
            answer: "Your team has 12 engineers.", context: "Team info exists.",
            question: "how big is my team?", extraAllowed: ["User's team has 12 engineers."])
        #expect(bad.isEmpty)
    }
}

@Suite struct AntiConfabulationPipelineTests {
    private func makeStack(chunkTexts: [String]) async throws -> (any ChunkRepository, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataChunkRepository(modelContainer: container)
        let source = UUID()
        var snapshots: [ChunkSnapshot] = []
        for (index, text) in chunkTexts.enumerated() {
            snapshots.append(ChunkSnapshot(sourceId: source, sourceType: .document, text: text,
                                           embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: index))
        }
        try await repo.insert(snapshots)
        return (repo, container)
    }

    private func pipeline(chunks: any ChunkRepository, gateway: MockModelGateway) -> RAGPipeline {
        let embedder = MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] })
        return RAGPipeline(corpus: CorpusCache(chunks: chunks, dimension: { try await embedder.dimension }),
                           embedder: embedder, search: VectorSearch(),
                           gateway: gateway, budgeter: TokenBudgeter(), availability: { .tierA })
    }

    @Test func fabricatedNumberTriggersRetryAndRetryWins() async throws {
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: "The dataset has 22,000 clips.", usedProvidedContext: true),
            RAGAnswer(answer: "The dataset has 5,800 clips.", usedProvidedContext: true, citedPassages: [1]),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("how many clips are in the dataset?", history: [])
        guard case .grounded(let answer, _, _) = result else {
            Issue.record("expected grounded, got \(result)"); return
        }
        #expect(answer.contains("5,800"))
        #expect(!answer.contains("22,000"))
        #expect(!answer.contains("⚠️"))                 // retry succeeded → no caveat
        #expect(await gateway.counts().generate == 2)   // exactly one corrective retry
    }

    @Test func persistentFabricationShipsWithHonestCaveat() async throws {
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: "It has 22,000 clips.", usedProvidedContext: true),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("how many clips are in the dataset?", history: [])
        guard case .grounded(let answer, _, _) = result else {
            Issue.record("expected grounded, got \(result)"); return
        }
        #expect(answer.contains("⚠️"))
        #expect(answer.contains("22000"))               // the unverified figure is named
    }

    @Test func supportedNumbersNeverRetry() async throws {
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "It has 5,800 clips.", usedProvidedContext: true))
        _ = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("how many clips?", history: [])
        #expect(await gateway.counts().generate == 1)   // no retry cost on clean answers
    }

    @Test func notFoundFlagYieldsNotFoundResult() async throws {
        let (chunks, _) = try await makeStack(chunkTexts: ["Unrelated content."])
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "I couldn't find anything about XQRT-9 in your knowledge.",
                                       usedProvidedContext: false, notFoundInContext: true))
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("what is XQRT-9?", history: [])
        guard case .notFound(let answer, _) = result else {
            Issue.record("expected notFound, got \(result)"); return
        }
        #expect(answer.contains("couldn't find"))
    }

    @Test func flagFlippingRetryStillGetsTheCaveat() async throws {
        // The retry can't dodge the caveat by flipping usedProvidedContext —
        // the deterministic backstop must not trust model self-reports.
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: "The dataset has 22,000 clips.", usedProvidedContext: true),
            RAGAnswer(answer: "It has 22,000 clips.", usedProvidedContext: false),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("how many clips are in the dataset?", history: [])
        guard case .conversational(let answer, _) = result else {
            Issue.record("expected conversational, got \(result)"); return
        }
        #expect(answer.contains("⚠️"))
    }

    @Test func honestNotFoundRetryIsAccepted() async throws {
        // A retry that drops the bad figure and admits not-found is the GOOD
        // outcome — no caveat, honest .notFound.
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: "The methodology used 42 stages.", usedProvidedContext: true),
            RAGAnswer(answer: "I couldn't find the number of stages in your documents.",
                      usedProvidedContext: false, notFoundInContext: true),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("how many stages did the methodology use?", history: [])
        guard case .notFound(let answer, _) = result else {
            Issue.record("expected notFound, got \(result)"); return
        }
        #expect(!answer.contains("⚠️"))
    }

    @Test func userStatedFiguresAreNotFlagged() async throws {
        // A figure the user gave in an earlier turn is legitimate support —
        // no wasted retry, no caveat.
        let (chunks, _) = try await makeStack(chunkTexts: ["The team ships weekly."])
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: "Your team of 12 engineers ships weekly.",
                                       usedProvidedContext: true))
        let history = [ChatTurn(role: .user, content: "we have 12 engineers on the team"),
                       ChatTurn(role: .assistant, content: "Noted!")]
        _ = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("how does my team ship?", history: history)
        #expect(await gateway.counts().generate == 1)
    }

    @Test func voiceStreamAppendsCaveatOnUnverifiableFigures() async throws {
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(respondReturn: "It has 22,000 clips.")
        var final = ""
        for try await cumulative in pipeline(chunks: chunks, gateway: gateway)
            .askStreaming("how many clips?", history: []) {
            final = cumulative
        }
        #expect(final.contains("double-check"))
        #expect(final.hasPrefix("It has 22,000 clips."))   // spoken text is preserved
    }

    @Test func voiceStreamStaysQuietOnSupportedFigures() async throws {
        let (chunks, _) = try await makeStack(chunkTexts: ["The dataset has 5,800 clips."])
        let gateway = MockModelGateway(respondReturn: "It has 5,800 clips.")
        var final = ""
        for try await cumulative in pipeline(chunks: chunks, gateway: gateway)
            .askStreaming("how many clips?", history: []) {
            final = cumulative
        }
        #expect(!final.contains("double-check"))
    }

    @Test func hardRulesAreInThePrompt() {
        // Regression lock on the anti-confabulation instructions.
        #expect(RAGPrompts.hybrid.contains("NEVER invent"))
        #expect(RAGPrompts.hybrid.contains("notFoundInContext"))
        #expect(RAGPrompts.hybrid.contains("exact wording"))
        #expect(RAGPrompts.hybrid.contains("negations"))
        #expect(RAGPrompts.hybrid.contains("Never repeat a figure"))
    }
}

@Suite struct DocumentIdentityPrefixTests {
    @Test func indexedDocumentChunksCarryTheTitle() async throws {
        let container = try ModelContainerFactory.inMemory()
        let docs = SwiftDataDocumentRepository(modelContainer: container)
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let id = UUID()
        try await docs.create(DocumentSnapshot(id: id, title: "Falcon Paper", fileName: "f.md",
                                               fileType: .md, textContent: "The dataset has 5,800 clips and many details worth chunking properly."))
        let indexer = RAGIndexer(documents: docs, sessions: sessions, chunks: chunks,
                                 embedder: MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] }))
        try await indexer.indexDocument(id: id)

        let stored = try await chunks.fetchAll()
        #expect(!stored.isEmpty)
        #expect(stored.allSatisfy { $0.text.hasPrefix("[Falcon Paper]") })
    }

    @Test func indexedSessionChunksCarryTheTitle() async throws {
        let container = try ModelContainerFactory.inMemory()
        let docs = SwiftDataDocumentRepository(modelContainer: container)
        let sessions = SwiftDataSessionRepository(modelContainer: container)
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        let id = UUID()
        try await sessions.create(SessionSnapshot(id: id, title: "Sprint Review"))
        try await sessions.appendSegment(SegmentSnapshot(
            sessionId: id, text: "We agreed to ship the beta next week after the review.",
            startTime: 0, endTime: 5), toSession: id)
        let indexer = RAGIndexer(documents: docs, sessions: sessions, chunks: chunks,
                                 embedder: MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] }))
        try await indexer.indexSession(id: id)

        let stored = try await chunks.fetchAll()
        #expect(!stored.isEmpty)
        #expect(stored.allSatisfy { $0.text.hasPrefix("[Sprint Review]") })
    }
}
