import Foundation
import FoundationModels

/// Guided-generation answer for the Ask feature. The model answers the user's
/// message and reports whether it actually used the provided knowledge context,
/// so the UI shows sources only for grounded answers — not for casual chat.
@Generable
nonisolated struct RAGAnswer: Codable, Equatable, Sendable {
    @Guide(description: "A helpful, concise answer to the user's message")
    var answer: String
    @Guide(description: "True ONLY if you used the provided context passages to answer; false for casual conversation or general knowledge")
    var usedProvidedContext: Bool

    @Guide(description: "Two or three short, natural follow-up questions the user might ask next", .count(0...3))
    var followUps: [String]

    init(answer: String = "", usedProvidedContext: Bool = false, followUps: [String] = []) {
        self.answer = answer
        self.usedProvidedContext = usedProvidedContext
        self.followUps = followUps
    }
}
