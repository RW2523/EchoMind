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

    private(set) var respondCalls = 0
    private(set) var generateCalls = 0

    init(overflowRespond: Int = 0, overflowGenerate: Int = 0,
         respondReturn: String = "partial summary bullet",
         summaryReturn: MeetingSummary = MeetingSummary(overview: "An overview."),
         ragAnswerReturn: RAGAnswer = RAGAnswer(answer: "An answer.", usedProvidedContext: true)) {
        self.overflowRespond = overflowRespond
        self.overflowGenerate = overflowGenerate
        self.respondReturn = respondReturn
        self.summaryReturn = summaryReturn
        self.ragAnswerReturn = ragAnswerReturn
    }

    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String {
        respondCalls += 1
        if overflowRespond > 0 { overflowRespond -= 1; throw ModelGatewayError.exceededContextWindow }
        return respondReturn
    }

    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type) async throws -> T {
        generateCalls += 1
        if overflowGenerate > 0 { overflowGenerate -= 1; throw ModelGatewayError.exceededContextWindow }
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
