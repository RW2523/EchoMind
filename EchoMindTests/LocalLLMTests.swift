import Testing
import Foundation
import FoundationModels
@testable import EchoMind

// A tiny Generable used to exercise the guided-JSON path end to end.
@Generable
private struct TestNote: Equatable {
    @Guide(description: "A short title") var title: String
    @Guide(description: "How many items") var count: Int
}

/// Scriptable stand-in for a real MLX engine — returns queued outputs in order.
private actor MockLLMEngine: LocalLLMEngine {
    nonisolated let contextSize: Int
    private var outputs: [Result<String, Error>]
    private var loaded: Bool
    private(set) var loadCalls = 0
    private(set) var completeCalls = 0

    init(contextSize: Int = 8_192, loaded: Bool = true, outputs: [Result<String, Error>]) {
        self.contextSize = contextSize
        self.loaded = loaded
        self.outputs = outputs
    }

    func isLoaded() async -> Bool { loaded }
    func load() async throws { loadCalls += 1; loaded = true }

    func complete(messages: [LLMMessage], maxTokens: Int) async throws -> String {
        completeCalls += 1
        guard !outputs.isEmpty else { throw LocalLLMEngineError.generationFailed("no scripted output") }
        return try outputs.removeFirst().get()
    }

    var loadCallCount: Int { loadCalls }
    var completeCallCount: Int { completeCalls }
}

@Suite struct GuidedJSONTests {
    @Test func extractsPlainObject() {
        #expect(GuidedJSON.extractJSONObject("prefix {\"a\":1} suffix") == "{\"a\":1}")
    }

    @Test func extractsFromCodeFence() {
        let raw = "Here you go:\n```json\n{\"title\":\"x\",\"count\":2}\n```"
        #expect(GuidedJSON.extractJSONObject(raw) == "{\"title\":\"x\",\"count\":2}")
    }

    @Test func handlesNestedObjects() {
        #expect(GuidedJSON.extractJSONObject("{\"a\":{\"b\":2}}") == "{\"a\":{\"b\":2}}")
    }

    @Test func ignoresBracesInsideStrings() {
        let raw = "{\"a\":\"has } brace\"}"
        #expect(GuidedJSON.extractJSONObject(raw) == raw)
    }

    @Test func returnsNilWhenNoObject() {
        #expect(GuidedJSON.extractJSONObject("no json here") == nil)
    }

    @Test func schemaJSONIsNonEmpty() throws {
        let schema = try GuidedJSON.schemaJSON(for: TestNote.self)
        #expect(!schema.isEmpty)
        #expect(schema.contains("title"))
    }

    @Test func decodesValidObject() throws {
        let note = try GuidedJSON.decode("{\"title\":\"Hello\",\"count\":3}", as: TestNote.self)
        #expect(note == TestNote(title: "Hello", count: 3))
    }

    @Test func decodeThrowsOnMissingObject() {
        #expect(throws: (any Error).self) {
            _ = try GuidedJSON.decode("not json", as: TestNote.self)
        }
    }
}

@Suite struct LocalLLMGatewayTests {
    @Test func respondReturnsRawCompletion() async throws {
        let engine = MockLLMEngine(outputs: [.success("hello there")])
        let gateway = LocalLLMGateway(engine: engine)
        let out = try await gateway.respond(instructions: "sys", prompt: "hi", maxOutputTokens: 64)
        #expect(out == "hello there")
    }

    @Test func generateSucceedsFirstTry() async throws {
        let engine = MockLLMEngine(outputs: [.success("{\"title\":\"A\",\"count\":1}")])
        let gateway = LocalLLMGateway(engine: engine)
        let note = try await gateway.generate(instructions: "make a note", prompt: "go", as: TestNote.self)
        #expect(note == TestNote(title: "A", count: 1))
    }

    @Test func generateRetriesThenSucceeds() async throws {
        let engine = MockLLMEngine(outputs: [
            .success("sorry, no json"),
            .success("{\"title\":\"B\",\"count\":2}"),
        ])
        let gateway = LocalLLMGateway(engine: engine)
        let note = try await gateway.generate(instructions: "x", prompt: "y", as: TestNote.self)
        #expect(note == TestNote(title: "B", count: 2))
        #expect(await engine.completeCallCount == 2)
    }

    @Test func generateFailsAfterRetriesExhausted() async {
        let engine = MockLLMEngine(outputs: [
            .success("nope"), .success("still nope"), .success("nope again"),
        ])
        let gateway = LocalLLMGateway(engine: engine, maxRetries: 2)
        await #expect(throws: ModelGatewayError.self) {
            _ = try await gateway.generate(instructions: "x", prompt: "y", as: TestNote.self)
        }
    }

    @Test func loadsEngineWhenNotYetLoaded() async throws {
        let engine = MockLLMEngine(loaded: false, outputs: [.success("ok")])
        let gateway = LocalLLMGateway(engine: engine)
        _ = try await gateway.respond(instructions: "s", prompt: "p", maxOutputTokens: 8)
        #expect(await engine.loadCallCount == 1)
    }
}
