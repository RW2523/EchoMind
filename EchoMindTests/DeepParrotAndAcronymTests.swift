import Testing
import Foundation
import SwiftData
@testable import EchoMind

// Second field report (chat export 2026-09-12): an off-topic statement got an
// OLD answer re-emitted twice (guard only checked the last turn), and "HHL
// stands for Hybrid Least Squares" sailed past the digits-only verifier.

@Suite struct AcronymVerifierTests {
    private let context = "The HHL (Harrow, Hassidim and Lloyd) algorithm solves linear systems."

    @Test func wrongInitialsAreFlagged() {
        let bad = AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for Hybrid Least Squares.", context: context)
        #expect(bad == ["HHL = Hybrid Least Squares"])
    }

    @Test func correctExpansionWithDifferentPunctuationPasses() {
        // Paper writes "Harrow, Hassidim and Lloyd"; answer hyphenates.
        let bad = AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for Harrow-Hassidim-Lloyd.", context: context)
        #expect(bad.isEmpty)
    }

    @Test func commaSeparatedDocumentWordingPasses() {
        // The document's own comma form must never be flagged — rule 7 tells the
        // model to use the passage's exact wording, so punishing it is perverse.
        let bad = AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for Harrow, Hassidim and Lloyd.", context: context)
        #expect(bad.isEmpty)
    }

    @Test func trailingClauseAfterCorrectExpansionPasses() {
        let bad = AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for Harrow-Hassidim-Lloyd and it solves linear systems efficiently.",
            context: context)
        #expect(bad.isEmpty)
    }

    @Test func isShortForVariantIsChecked() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "HHL is short for Hybrid Least Squares.",
            context: context) == ["HHL = Hybrid Least Squares"])
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "HHL is short for Harrow, Hassidim and Lloyd.",
            context: context).isEmpty)
    }

    @Test func isAnAbbreviationForVariantIsChecked() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "HHL is an abbreviation for Hybrid Least Squares.",
            context: context) == ["HHL = Hybrid Least Squares"])
    }

    @Test func phraseWithoutDirectAssertionIsIgnored() {
        // "…what HHL stands for, then…" asserts no expansion; the next clause
        // must not be mistaken for one.
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "The paper explains what HHL stands for, then evaluates it.",
            context: context).isEmpty)
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for. Nothing else.", context: context).isEmpty)
    }

    @Test func quotedExpansionIsChecked() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for \"Harrow, Hassidim and Lloyd\".",
            context: context).isEmpty)
    }

    @Test func matchingInitialsButAbsentFromContextIsFlagged() {
        // Consistent-looking expansion invented from general knowledge.
        let bad = AnswerVerifier.unsupportedExpansions(
            answer: "QSVM stands for Quantum Support Vector Machine.",
            context: "The paper evaluates QSVM on two datasets.")
        #expect(bad.count == 1)
    }

    @Test func answersWithoutExpansionClaimsPass() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "The dataset has 5,800 clips.", context: context).isEmpty)
    }
}

@Suite struct RecentExchangeTests {
    @Test func pairsEachAnswerWithItsQuestionAndKeepsTheLastFour() {
        var history: [ChatTurn] = []
        for index in 1...6 {
            history.append(ChatTurn(role: .user, content: "question \(index)"))
            history.append(ChatTurn(role: .assistant, content: "answer \(index)"))
        }
        let pairs = RAGPipeline.recentExchanges(history: history)
        #expect(pairs.map(\.question) == ["question 3", "question 4", "question 5", "question 6"])
        #expect(pairs.map(\.answer) == ["answer 3", "answer 4", "answer 5", "answer 6"])
    }

    @Test func unansweredUserTurnsAreSkipped() {
        // Voice barge-in can leave a user turn with no assistant reply.
        let history = [ChatTurn(role: .user, content: "interrupted question"),
                       ChatTurn(role: .user, content: "second question"),
                       ChatTurn(role: .assistant, content: "second answer")]
        let pairs = RAGPipeline.recentExchanges(history: history)
        #expect(pairs.count == 1)
        #expect(pairs[0].question == "second question")
        #expect(pairs[0].answer == "second answer")
    }

    @Test func leadingAssistantTurnPairsWithEmptyQuestion() {
        // Documents current behavior: a history that starts mid-conversation
        // pairs the orphan answer with "" — isSameQuestion("", x) is false, so
        // the guard stays armed against that answer.
        let pairs = RAGPipeline.recentExchanges(
            history: [ChatTurn(role: .assistant, content: "orphan answer")])
        #expect(pairs.count == 1)
        #expect(pairs[0].question.isEmpty)
    }

    @Test func emptyHistoryYieldsNoPairs() {
        #expect(RAGPipeline.recentExchanges(history: []).isEmpty)
    }

    @Test func appendedCaveatsAreStrippedFromExchangeAnswers() {
        // A stored answer carrying a verification caveat is ~80 chars longer
        // than its body — without stripping, a re-emitted body slips under
        // isNearDuplicate's 0.75 length ratio and the parrot goes undetected.
        let body = "The proposed loss outperforms cross entropy and MSE by 12.5% at threshold T=5 using the 3D CNN model."
        let stored = body + "\n\n⚠️ Double-check these against your documents — I couldn't verify: 12.5."
        let pairs = RAGPipeline.recentExchanges(
            history: [ChatTurn(role: .user, content: "by how much does the loss outperform?"),
                      ChatTurn(role: .assistant, content: stored)])
        #expect(pairs[0].answer == body)
        #expect(RAGPipeline.isNearDuplicate(body, of: pairs[0].answer))
        #expect(!RAGPipeline.isNearDuplicate(body, of: stored))   // the bug being prevented
    }
}

@Suite struct QuestionEquivalenceTests {
    @Test func repeatsAndParaphrasesOfSameQuestionMatch() {
        #expect(RAGPipeline.isSameQuestion("Who is Tristan Buckmaster?",
                                           "Who is Tristan Buckmaster?"))
        #expect(RAGPipeline.isSameQuestion("who is tristan buckmaster",
                                           "Who is Tristan Buckmaster?"))
    }

    @Test func differentQuestionsDoNotMatch() {
        #expect(!RAGPipeline.isSameQuestion(
            "The new iPhone duo is super affordable according to users.",
            "Under what five conditions does Tumblr disclose user information?"))
    }
}

@Suite struct DeepParrotGuardTests {
    private func makeStack() async throws -> (any ChunkRepository, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataChunkRepository(modelContainer: container)
        try await repo.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .document,
                                             text: "The iPhone duo costs 2,000 dollars, which reviewers called expensive.",
                                             embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        return (repo, container)
    }

    private func pipeline(chunks: any ChunkRepository, gateway: MockModelGateway) -> RAGPipeline {
        let embedder = MockEmbeddingService(dim: 3, map: { _ in [1, 0, 0] })
        return RAGPipeline(corpus: CorpusCache(chunks: chunks, dimension: { try await embedder.dimension }),
                           embedder: embedder, search: VectorSearch(),
                           gateway: gateway, budgeter: TokenBudgeter(), availability: { .tierA })
    }

    private let staleAnswer = "Tumblr reserves the right to disclose user information without consent under five conditions related to safety, legal compliance, and platform protection policies."
    private var history: [ChatTurn] {
        [ChatTurn(role: .user, content: "Under what conditions does Tumblr disclose information?"),
         ChatTurn(role: .assistant, content: staleAnswer),
         ChatTurn(role: .user, content: "What does the payment processor send back?"),
         ChatTurn(role: .assistant, content: "Tumblr receives a token and the card's last four digits back from its Payment Processor.")]
    }

    @Test func echoOfOlderAnswerTriggersRetryAndFreshRetryWins() async throws {
        let (chunks, _) = try await makeStack()
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: staleAnswer, usedProvidedContext: false),
            RAGAnswer(answer: "The transcript says the iPhone duo costs 2,000 dollars and reviewers found it expensive — not affordable.",
                      usedProvidedContext: true, citedPassages: [1]),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("The new iPhone duo is super affordable according to users.", history: history)
        #expect(result.spokenText.contains("2,000"))
        #expect(!result.spokenText.contains("Tumblr"))
        #expect(await gateway.counts().generate == 2)
    }

    @Test func persistentEchoShipsClarificationNotStaleAnswer() async throws {
        let (chunks, _) = try await makeStack()
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: staleAnswer, usedProvidedContext: false),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("The new iPhone duo is super affordable according to users.", history: history)
        guard case .conversational(let answer, let followUps) = result else {
            Issue.record("expected conversational, got \(result)"); return
        }
        #expect(!answer.contains("Tumblr"))
        #expect(answer.contains("rephrase"))
        // The fixed clarification carries no model-suggested follow-ups — the
        // stale draft's suggestions would be about the WRONG answer.
        #expect(followUps.isEmpty)
    }

    @Test func repeatedQuestionMayRepeatItsAnswer() async throws {
        // Asking the same question again is NOT parroting.
        let (chunks, _) = try await makeStack()
        let repeated = "Under what conditions does Tumblr disclose information?"
        let gateway = MockModelGateway(
            ragAnswerReturn: RAGAnswer(answer: staleAnswer, usedProvidedContext: false))
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask(repeated, history: history)
        #expect(result.spokenText.contains("Tumblr"))
        #expect(await gateway.counts().generate == 1)      // no retry wasted
    }

    @Test func acronymConfabulationGetsCaveatWhenPersistent() async throws {
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        try await chunks.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .document,
                                               text: "The HHL (Harrow, Hassidim and Lloyd) algorithm solves linear systems.",
                                               embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        let gateway = MockModelGateway(ragAnswerSequence: [
            RAGAnswer(answer: "HHL stands for Hybrid Least Squares.", usedProvidedContext: true),
        ])
        let result = try await pipeline(chunks: chunks, gateway: gateway)
            .ask("what does HHL stand for?", history: [])
        #expect(result.spokenText.contains("⚠️"))
        #expect(result.spokenText.contains("HHL = Hybrid Least Squares"))
        #expect(await gateway.counts().generate == 2)      // one corrective retry
    }

    @Test func voiceStreamOwnsUpToParrotedOlderAnswer() async throws {
        // Voice can't retry mid-stream, but a stale echo must not end the turn
        // presented as a fresh answer — the guard appends a spoken correction.
        let (chunks, _) = try await makeStack()
        let gateway = MockModelGateway(respondReturn: staleAnswer)
        var final = ""
        for try await cumulative in pipeline(chunks: chunks, gateway: gateway)
            .askStreaming("The new iPhone duo is super affordable according to users.", history: history) {
            final = cumulative
        }
        #expect(final.contains("rephrase"))
        #expect(final.hasPrefix(staleAnswer))   // already-spoken text preserved
    }

    @Test func voiceStreamAllowsRepeatForRepeatedQuestion() async throws {
        let (chunks, _) = try await makeStack()
        let gateway = MockModelGateway(respondReturn: staleAnswer)
        var final = ""
        for try await cumulative in pipeline(chunks: chunks, gateway: gateway)
            .askStreaming("Under what conditions does Tumblr disclose information?", history: history) {
            final = cumulative
        }
        #expect(!final.contains("rephrase"))
    }

    @Test func voiceStreamAppendsCaveatOnUnsupportedExpansion() async throws {
        // The digits-only check can't see "HHL stands for Hybrid Least Squares"
        // (no numbers) — the voice path needs the expansion check too.
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        try await chunks.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .document,
                                               text: "The HHL (Harrow, Hassidim and Lloyd) algorithm solves linear systems.",
                                               embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        let gateway = MockModelGateway(respondReturn: "HHL stands for Hybrid Least Squares.")
        var final = ""
        for try await cumulative in pipeline(chunks: chunks, gateway: gateway)
            .askStreaming("what does HHL stand for?", history: []) {
            final = cumulative
        }
        #expect(final.contains("double-check"))
        #expect(final.hasPrefix("HHL stands for Hybrid Least Squares."))   // spoken text preserved
    }

    @Test func voiceStreamStaysQuietOnSupportedExpansion() async throws {
        let container = try ModelContainerFactory.inMemory()
        let chunks = SwiftDataChunkRepository(modelContainer: container)
        try await chunks.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .document,
                                               text: "The HHL (Harrow, Hassidim and Lloyd) algorithm solves linear systems.",
                                               embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        let gateway = MockModelGateway(respondReturn: "HHL stands for Harrow, Hassidim and Lloyd.")
        var final = ""
        for try await cumulative in pipeline(chunks: chunks, gateway: gateway)
            .askStreaming("what does HHL stand for?", history: []) {
            final = cumulative
        }
        #expect(!final.contains("double-check"))
    }

    @Test func newPromptRulesAreLocked() {
        #expect(RAGPrompts.hybrid.contains("NEVER pad a list"))
        #expect(RAGPrompts.hybrid.contains("Expand an acronym only"))
        #expect(RAGPrompts.hybrid.contains("Outside your saved knowledge"))
    }
}

// Review-round regressions: the guards must never punish legitimate answers.
@Suite struct ParrotGuardFalsePositiveTests {
    @Test func paraphrasedReAskCountsAsSameQuestion() {
        // Jaccard punished added qualifier words; overlap coefficient must not.
        #expect(RAGPipeline.isSameQuestion(
            "Under what conditions does Tumblr disclose information?",
            "Under what five conditions does Tumblr disclose user information to third parties?"))
    }

    @Test func offTopicStatementIsStillADifferentQuestion() {
        #expect(!RAGPipeline.isSameQuestion(
            "The new iPhone duo is super affordable according to users.",
            "Under what conditions does Tumblr disclose information?"))
    }

    @Test func explicitRepeatRequestsAreRecognized() {
        #expect(RAGPipeline.requestsRepeat("Sorry, can you repeat that?"))
        #expect(RAGPipeline.requestsRepeat("say that again please"))
        #expect(!RAGPipeline.requestsRepeat("What did the paper say about recall?"))
    }
}

@Suite struct AcronymFalsePositiveTests {
    @Test func stopwordInitialsAreSupported() {
        // POW = Prisoner Of War: the O comes from a stopword.
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "POW stands for prisoner of war.",
            context: "The memo defines POW as prisoner of war status for detainees.").isEmpty)
    }

    @Test func verbatimNonInitialismInContextIsSupported() {
        // ID = identification: initials can't match; the document saying it is enough.
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "ID is short for identification.",
            context: "Users provide identification (ID) when registering.").isEmpty)
    }

    @Test func digitOnlyTokensAreNotAcronyms() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "On the scale, 45 stands for partial compliance.",
            context: "Nothing relevant.").isEmpty)
    }

    @Test func standsFormallyIsNotATrigger() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "The committee stands formally against the proposal.",
            context: "Nothing relevant.").isEmpty)
    }

    @Test func hyphenatedAcronymSurvivesExtraction() {
        // "3D-CNN" must not be truncated to "CNN"; verbatim context support passes it.
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "3D-CNN stands for three dimensional convolutional neural network.",
            context: "We use a three dimensional convolutional neural network (3D-CNN).").isEmpty)
    }

    @Test func pluralAndDiacriticVariantsMatch() {
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "GAN stands for Generative Adversarial Network.",
            context: "Generative Adversarial Networks (GANs) are used throughout.").isEmpty)
    }

    @Test func wrongExpansionIsStillFlagged() {
        // The precision loosening must not let the original field bug back in.
        #expect(AnswerVerifier.unsupportedExpansions(
            answer: "HHL stands for Hybrid Least Squares.",
            context: "The HHL (Harrow, Hassidim and Lloyd) algorithm uses least squares methods with hybrid quantum-classical solvers.")
            == ["HHL = Hybrid Least Squares"])
    }
}
