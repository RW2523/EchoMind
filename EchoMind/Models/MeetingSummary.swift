import Foundation
import FoundationModels

/// Guided-generation summary schema (§5.4). Kept flat with short @Guide strings
/// — every schema character is input tokens in the reduce call. `Codable` is
/// ours (independent of `Generable`) for `Session.summaryJSON` persistence.
@Generable
nonisolated struct MeetingSummary: Codable, Equatable, Sendable {
    @Guide(description: "2-4 sentence overview of what the meeting covered")
    var overview: String
    @Guide(description: "Concrete decisions that were made, one per entry")
    var keyDecisions: [String]
    var actionItems: [ActionItem]
    var risks: [String]
    var openQuestions: [String]

    @Generable
    nonisolated struct ActionItem: Codable, Equatable, Sendable {
        var text: String
        @Guide(description: "Person responsible, only if explicitly named")
        var owner: String?
    }

    init(overview: String = "", keyDecisions: [String] = [], actionItems: [ActionItem] = [],
         risks: [String] = [], openQuestions: [String] = []) {
        self.overview = overview
        self.keyDecisions = keyDecisions
        self.actionItems = actionItems
        self.risks = risks
        self.openQuestions = openQuestions
    }
}
