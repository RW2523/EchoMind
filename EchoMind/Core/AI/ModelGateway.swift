import Foundation
import FoundationModels

/// The V1.1 seam (§5.2 / spec §10). Call sites take `any ModelGateway`; a future
/// PCC/third-party implementation drops in with no call-site changes. `Generable`
/// is the one framework type allowed through the seam.
nonisolated protocol ModelGateway: Sendable {
    /// Free-form text. One fresh underlying session per call.
    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String
    /// Guided generation into a @Generable type. One fresh session per call.
    /// `maxOutputTokens` is the caller's output budget — the same number it reserves
    /// when packing input — so guided calls are no longer coupled to the summarizer's cap.
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T
}

extension ModelGateway {
    /// Convenience for callers with no special budget: uses the shared guided default.
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type) async throws -> T {
        try await generate(instructions: instructions, prompt: prompt, as: type,
                           maxOutputTokens: ModelGatewayDefaults.guidedOutputTokens)
    }
}

nonisolated enum ModelGatewayDefaults {
    /// Default output cap for guided generation. Sized to comfortably fit a grounded
    /// RAG answer (text + sources + follow-ups); small guided calls (category names,
    /// memory updates) never approach it. Kept well under the 4,096-token floor.
    static let guidedOutputTokens = 1000
}

nonisolated enum ModelGatewayError: Error, Equatable {
    case exceededContextWindow
    case modelUnavailable(AvailabilityStatus)
    case guardrailViolation
    case generationFailed(String)
}
