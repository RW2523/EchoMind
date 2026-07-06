import Foundation
import FoundationModels

/// ModelGateway over SystemLanguageModel/LanguageModelSession (§5.2). Holds NO
/// session property — a fresh `LanguageModelSession` is built and discarded per
/// call, so "never accumulate history" is structural, not a convention.
nonisolated struct FoundationModelService: ModelGateway {
    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(maximumResponseTokens: maxOutputTokens))
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        } catch {
            throw ModelGatewayError.generationFailed(String(describing: error))
        }
    }

    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type) async throws -> T {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                generating: type,
                options: GenerationOptions(maximumResponseTokens: SummaryPrompts.reduceOutputTokens))
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error)
        } catch {
            throw ModelGatewayError.generationFailed(String(describing: error))
        }
    }

    private static func mapped(_ error: LanguageModelSession.GenerationError) -> ModelGatewayError {
        switch error {
        case .exceededContextWindowSize:
            return .exceededContextWindow
        case .guardrailViolation, .refusal:
            return .guardrailViolation
        default:
            return .generationFailed(String(describing: error))
        }
    }
}
