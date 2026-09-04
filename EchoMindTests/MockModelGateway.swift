import Foundation
import FoundationModels
@testable import EchoMind

/// Scriptable gateway: canned responses + injectable overflow for retry tests.
actor MockModelGateway: ModelGateway {
    private var overflowRespond: Int
    private var overflowGenerate: Int
    private let respondReturn: String
    private let summaryReturn: MeetingSummary
    private let ragAnswerReturn: RAGAnswer
    /// When non-empty, RAGAnswer requests consume this sequence in order (the
    /// last element repeats) — for testing retry flows (verifier, parrot guard).
    private var ragAnswerSequence: [RAGAnswer]

    private(set) var respondCalls = 0
    private(set) var generateCalls = 0
    private(set) var lastGeneratePrompt: String?
    private(set) var lastRespondPrompt: String?

    init(overflowRespond: Int = 0, overflowGenerate: Int = 0,
         respondReturn: String = "partial summary bullet",
         summaryReturn: MeetingSummary = MeetingSummary(overview: "An overview."),
         ragAnswerReturn: RAGAnswer = RAGAnswer(answer: "An answer.", usedProvidedContext: true),
         ragAnswerSequence: [RAGAnswer] = []) {
        self.overflowRespond = overflowRespond
        self.overflowGenerate = overflowGenerate
        self.respondReturn = respondReturn
        self.summaryReturn = summaryReturn
        self.ragAnswerReturn = ragAnswerReturn
        self.ragAnswerSequence = ragAnswerSequence
    }

    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String {
        respondCalls += 1
        lastRespondPrompt = prompt
        if overflowRespond > 0 { overflowRespond -= 1; throw ModelGatewayError.exceededContextWindow }
        return respondReturn
    }

    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T {
        generateCalls += 1
        lastGeneratePrompt = prompt
        if overflowGenerate > 0 { overflowGenerate -= 1; throw ModelGatewayError.exceededContextWindow }
        if !ragAnswerSequence.isEmpty, T.self == RAGAnswer.self {
            let next = ragAnswerSequence.count > 1 ? ragAnswerSequence.removeFirst() : ragAnswerSequence[0]
            if let answer = next as? T { return answer }
        }
        if let answer = ragAnswerReturn as? T { return answer }
        if let summary = summaryReturn as? T { return summary }
        throw ModelGatewayError.generationFailed("unexpected generable type")
    }
}

@MainActor
final class MockAvailabilityProvider: AvailabilityProviding {
    var status: AvailabilityStatus
    init(status: AvailabilityStatus = .tierA) { self.status = status }
    func refresh() {}
}

extension MockModelGateway {
    func counts() -> (respond: Int, generate: Int) { (respondCalls, generateCalls) }
}
