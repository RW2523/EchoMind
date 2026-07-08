import Foundation

/// A prior turn passed to the RAG pipeline for multi-turn memory (V2 §A1).
nonisolated struct ChatTurn: Sendable, Equatable {
    let role: MessageRole
    let content: String
}
