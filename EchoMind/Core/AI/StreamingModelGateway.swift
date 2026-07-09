import Foundation

/// Optional streaming capability alongside `ModelGateway` (Voice Agent V2). A
/// backend that can emit tokens as it generates conforms; callers that want
/// streaming check `as? StreamingModelGateway` and fall back to a one-shot stream
/// otherwise — so nothing breaks for non-streaming backends.
nonisolated protocol StreamingModelGateway: Sendable {
    /// Yields the **cumulative** answer text as it grows (matching Apple FM's
    /// snapshot model). Consumers diff against what they've already used.
    func stream(instructions: String, prompt: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, Error>
}

extension ModelGateway {
    /// Wrap a non-streaming `respond` as a single-emission stream, so a uniform
    /// streaming code path works for every backend.
    nonisolated func oneShotStream(instructions: String, prompt: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await respond(instructions: instructions, prompt: prompt,
                                                 maxOutputTokens: maxOutputTokens)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
