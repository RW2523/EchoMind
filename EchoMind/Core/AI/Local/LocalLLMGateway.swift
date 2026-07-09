import Foundation
import FoundationModels

/// A `ModelGateway` backed by any `LocalLLMEngine` (V2 §B2). This is what makes
/// "full AI with Apple Intelligence off" true: call sites keep using the exact
/// same `respond` / `generate` seam, and guided generation is emulated by asking
/// the model for schema-valid JSON and decoding it via `GuidedJSON`, retrying a
/// couple of times before surfacing failure.
nonisolated struct LocalLLMGateway: ModelGateway {
    let engine: any LocalLLMEngine
    let maxRetries: Int

    init(engine: any LocalLLMEngine, maxRetries: Int = 2) {
        self.engine = engine
        self.maxRetries = maxRetries
    }

    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String {
        try await ensureLoaded()
        let messages = [LLMMessage(.system, instructions), LLMMessage(.user, prompt)]
        do {
            return try await engine.complete(messages: messages, maxTokens: maxOutputTokens)
        } catch {
            throw Self.mapped(error)
        }
    }

    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T {
        try await ensureLoaded()
        let guidance = try GuidedJSON.instruction(for: type)
        var system = instructions + "\n\n" + guidance
        var lastError: Error?

        for attempt in 0...maxRetries {
            let messages = [LLMMessage(.system, system), LLMMessage(.user, prompt)]
            do {
                let raw = try await engine.complete(messages: messages, maxTokens: maxOutputTokens)
                return try GuidedJSON.decode(raw, as: type)
            } catch {
                lastError = error
                // Tighten the instruction on the next pass with a corrective nudge.
                if attempt < maxRetries {
                    system = instructions + "\n\n" + guidance +
                        "\n\nYour previous reply was not valid JSON for the schema. " +
                        "Return ONLY the JSON object this time."
                }
            }
        }
        throw ModelGatewayError.generationFailed(
            "local guided generation failed after \(maxRetries + 1) attempts: " +
            (lastError.map { String(describing: $0) } ?? "unknown"))
    }

    private func ensureLoaded() async throws {
        if await engine.isLoaded() { return }
        do { try await engine.load() }
        catch { throw Self.mapped(error) }
    }

    private static func mapped(_ error: Error) -> ModelGatewayError {
        if let e = error as? ModelGatewayError { return e }
        if let e = error as? LocalLLMEngineError {
            switch e {
            case .engineUnavailable, .notLoaded, .loadFailed:
                return .modelUnavailable(.tierB(.modelNotReady))
            case .cancelled, .generationFailed:
                return .generationFailed(String(describing: e))
            }
        }
        return .generationFailed(String(describing: error))
    }
}
