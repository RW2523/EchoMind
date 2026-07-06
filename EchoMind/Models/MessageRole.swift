import Foundation

/// Author of a `ChatMessage` in the Ask feature (Phase 8). Stored as `roleRaw`.
nonisolated enum MessageRole: String, Codable, Sendable, CaseIterable, Hashable {
    case user
    case assistant
}
