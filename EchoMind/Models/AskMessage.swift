import Foundation

/// A resolved source citation for display in the Ask UI.
nonisolated struct AskSource: Identifiable, Equatable {
    let id: UUID
    let title: String
    let detail: String?      // "Page 3" or "02:15"
    let preview: String?
    let sourceId: UUID
    let sourceType: SourceType
    let pageNumber: Int?
    let timestamp: TimeInterval?
}

/// A chat message prepared for rendering (persisted content + resolved sources).
nonisolated struct AskMessage: Identifiable, Equatable {
    enum Kind: Equatable { case user, grounded, notFound, retrievalOnly, plain }
    let id: UUID
    let role: MessageRole
    let content: String
    let sources: [AskSource]
    let kind: Kind
}
