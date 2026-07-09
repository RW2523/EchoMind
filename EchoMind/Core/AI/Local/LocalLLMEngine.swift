import Foundation

/// Raw text-completion seam for an on-device LLM (V2 §B2, Phase 14). Deliberately
/// dumb: messages in, text out. Everything smart — chat templating, JSON-guided
/// generation, retries, routing — lives above this in `LocalLLMGateway`, so the
/// only thing a concrete engine (MLX today, llama.cpp tomorrow) must do is turn a
/// list of chat messages into a completion. Keeps the package-specific surface
/// tiny and swappable.
nonisolated protocol LocalLLMEngine: Sendable {
    /// Model context window in tokens (drives `TokenBudgeter`).
    var contextSize: Int { get }
    /// Loads weights into memory. Idempotent; may download on first call.
    func load() async throws
    /// Whether `load()` has completed and the engine is ready to generate.
    func isLoaded() async -> Bool
    /// One completion. Implementations apply the model's own chat template.
    func complete(messages: [LLMMessage], maxTokens: Int) async throws -> String
}

/// A single chat-format turn handed to the engine.
nonisolated struct LLMMessage: Sendable, Equatable {
    nonisolated enum Role: String, Sendable { case system, user, assistant }
    let role: Role
    let content: String

    init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

nonisolated enum LocalLLMEngineError: Error, Equatable {
    case notLoaded
    case loadFailed(String)
    case generationFailed(String)
    case cancelled
    case engineUnavailable   // package not linked in this build
}
