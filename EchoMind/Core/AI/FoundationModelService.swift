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

extension FoundationModelService: StreamingModelGateway {
    func stream(instructions: String, prompt: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = LanguageModelSession(instructions: instructions)
                do {
                    let responses = session.streamResponse(
                        to: prompt,
                        options: GenerationOptions(maximumResponseTokens: maxOutputTokens))
                    // Each snapshot's `content` is the cumulative answer text so far.
                    for try await snapshot in responses {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.mapped(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
