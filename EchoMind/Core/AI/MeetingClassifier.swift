import Foundation
import FoundationModels

/// AI label for a meeting cluster (R2). Small schema — a category name plus a few
/// topic tags — so the classify call is cheap (~80 output tokens).
@Generable
nonisolated struct MeetingCategory: Codable, Equatable, Sendable {
    @Guide(description: "A short 1-3 word name for this meeting type, e.g. 'Weekly Standup', 'Client Call', '1:1'")
    var category: String
    @Guide(description: "Up to 3 short topic tags", .count(0...3))
    var topics: [String]

    init(category: String = "General", topics: [String] = []) {
        self.category = category
        self.topics = topics
    }
}

nonisolated protocol MeetingClassifying: Sendable {
    /// Name a meeting from its overview. `existingName` (the cluster's current
    /// canonical name) nudges the model to keep names stable across sessions.
    func classify(overview: String, existingName: String?) async throws -> MeetingCategory
}

nonisolated struct MeetingClassifier: MeetingClassifying {
    let gateway: any ModelGateway

    private static let base = """
    Classify this meeting into a short, reusable category name (1-3 words) plus up \
    to three topic tags. Prefer stable, general names that many similar meetings \
    could share (e.g. "Weekly Standup", not "Tuesday's standup about the API").
    """

    func classify(overview: String, existingName: String?) async throws -> MeetingCategory {
        let instructions: String
        if let existingName, !existingName.isEmpty {
            instructions = """
            \(Self.base)
            Similar meetings are already grouped under "\(existingName)". Reuse that \
            exact name unless it's clearly wrong for this meeting.
            """
        } else {
            instructions = Self.base
        }
        return try await gateway.generate(
            instructions: instructions,
            prompt: "Meeting summary:\n\(overview)",
            as: MeetingCategory.self)
    }
}
