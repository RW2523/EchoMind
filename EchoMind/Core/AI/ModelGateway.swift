import Foundation
import FoundationModels

/// The V1.1 seam (§5.2 / spec §10). Call sites take `any ModelGateway`; a future
/// PCC/third-party implementation drops in with no call-site changes. `Generable`
/// is the one framework type allowed through the seam.
nonisolated protocol ModelGateway: Sendable {
    /// Free-form text. One fresh underlying session per call.
    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String
    /// Guided generation into a @Generable type. One fresh session per call.
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type) async throws -> T
}

nonisolated enum ModelGatewayError: Error, Equatable {
    case exceededContextWindow
    case modelUnavailable(AvailabilityStatus)
    case guardrailViolation
    case generationFailed(String)
}
