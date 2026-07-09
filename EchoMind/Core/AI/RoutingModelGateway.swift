import Foundation
import FoundationModels

/// The `ModelGateway` the app actually injects (V2 §B4): it consults `FeatureRouter`
/// per call and dispatches to Apple Foundation Models or a local LLM, or throws
/// `modelUnavailable` when neither may run (letting RAG degrade to retrieval-only).
/// Same seam as before — summarizer and RAG don't know routing exists.
nonisolated struct RoutingModelGateway: ModelGateway {
    nonisolated struct Context: Sendable {
        let availability: AvailabilityStatus
        let localModelID: String?
        let preference: AIPreference
        let thermal: ThermalLevel
    }

    let apple: any ModelGateway
    /// nil when no local engine is linked/downloaded — router then never picks local.
    let local: (any ModelGateway)?
    let router: FeatureRouter
    /// Snapshot of routing inputs, sampled fresh per call (availability, heat, prefs
    /// all change at runtime).
    let context: @Sendable () async -> Context

    init(apple: any ModelGateway,
         local: (any ModelGateway)?,
         router: FeatureRouter = FeatureRouter(),
         context: @escaping @Sendable () async -> Context) {
        self.apple = apple
        self.local = local
        self.router = router
        self.context = context
    }

    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String {
        try await select().respond(instructions: instructions, prompt: prompt, maxOutputTokens: maxOutputTokens)
    }

    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type, maxOutputTokens: Int) async throws -> T {
        try await select().generate(instructions: instructions, prompt: prompt, as: type, maxOutputTokens: maxOutputTokens)
    }

    private func select() async throws -> any ModelGateway {
        let ctx = await context()
        // Suppress the local id entirely when no local gateway is wired, so the
        // router can never route to a backend we can't serve.
        let effectiveLocalID = local == nil ? nil : ctx.localModelID
        switch router.backend(availability: ctx.availability,
                              localModelID: effectiveLocalID,
                              preference: ctx.preference,
                              thermal: ctx.thermal) {
        case .appleFoundation:
            return apple
        case .local:
            return local ?? apple      // effectiveLocalID guarantees local != nil here
        case .retrievalOnly:
            throw ModelGatewayError.modelUnavailable(ctx.availability)
        }
    }
}

extension RoutingModelGateway: StreamingModelGateway {
    func stream(instructions: String, prompt: String, maxOutputTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let gateway = try await select()
                    let source = (gateway as? StreamingModelGateway)?
                        .stream(instructions: instructions, prompt: prompt, maxOutputTokens: maxOutputTokens)
                        ?? gateway.oneShotStream(instructions: instructions, prompt: prompt, maxOutputTokens: maxOutputTokens)
                    for try await chunk in source { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
