import Testing
import Foundation
@testable import EchoMind

@MainActor
private final class MockVoiceInput: VoiceInput {
    var finalTranscript: String
    var partials: [String]
    var throwOnStart = false
    private(set) var stopCount = 0

    init(final: String, partials: [String] = []) {
        self.finalTranscript = final
        self.partials = partials
    }

    func start() async throws -> AsyncStream<String> {
        if throwOnStart { throw VoiceInputError.microphoneDenied }
        let partials = self.partials
        return AsyncStream { continuation in
            for partial in partials { continuation.yield(partial) }
            continuation.finish()
        }
    }

    func stop() async -> String { stopCount += 1; return finalTranscript }
}

@MainActor
private final class MockSynthesizer: SpeechSynthesizing {
    let available: Bool
    let blockUntilStopped: Bool
    private(set) var spokenText: String?
    private(set) var spokenTexts: [String] = []
    private(set) var stopped = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(available: Bool = true, blockUntilStopped: Bool = false) {
        self.available = available
        self.blockUntilStopped = blockUntilStopped
    }

    nonisolated var isAvailable: Bool { true }

    func speak(_ text: String) async {
        spokenText = text
        spokenTexts.append(text)
        if blockUntilStopped {
            await withCheckedContinuation { self.continuation = $0 }
        }
    }

    func stop() {
        stopped = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class QuestionSink {
    var count = 0
    var lastQuestion: String?
    var answer: String?
    init(answer: String?) { self.answer = answer }
    func handle(_ q: String) async -> String? { count += 1; lastQuestion = q; return answer }
}

@Suite @MainActor struct VoiceSessionControllerTests {
    @Test func startListeningEntersListeningAndStreamsPartials() async {
        let input = MockVoiceInput(final: "hello there", partials: ["hello", "hello there"])
        let sink = QuestionSink(answer: "hi")
        let controller = VoiceSessionController(input: input, synthesizer: MockSynthesizer(),
                                                onQuestion: sink.handle)
        await controller.startListening()
        #expect(controller.state == .listening)
        for _ in 0..<20 where controller.partialTranscript != "hello there" { await Task.yield() }
        #expect(controller.partialTranscript == "hello there")
    }

    @Test func fullTurnSpeaksAnswerThenReturnsToIdle() async {
        let input = MockVoiceInput(final: "what is the refund policy")
        let synth = MockSynthesizer()
        let sink = QuestionSink(answer: "You have 30 days.")
        let controller = VoiceSessionController(input: input, synthesizer: synth, onQuestion: sink.handle)

        await controller.startListening()
        await controller.finishAndAsk()

        #expect(sink.lastQuestion == "what is the refund policy")
        #expect(synth.spokenText == "You have 30 days.")
        #expect(controller.state == .idle)
    }

    @Test func emptyTranscriptSkipsAskingAndIdles() async {
        let input = MockVoiceInput(final: "   ")
        let sink = QuestionSink(answer: "unused")
        let controller = VoiceSessionController(input: input, synthesizer: MockSynthesizer(),
                                                onQuestion: sink.handle)
        await controller.startListening()
        await controller.finishAndAsk()
        #expect(sink.count == 0)
        #expect(controller.state == .idle)
    }

    @Test func nilAnswerReturnsToIdleWithoutSpeaking() async {
        let input = MockVoiceInput(final: "hi")
        let synth = MockSynthesizer()
        let sink = QuestionSink(answer: nil)
        let controller = VoiceSessionController(input: input, synthesizer: synth, onQuestion: sink.handle)
        await controller.startListening()
        await controller.finishAndAsk()
        #expect(synth.spokenText == nil)
        #expect(controller.state == .idle)
    }

    @Test func startFailureSetsFailedState() async {
        let input = MockVoiceInput(final: "")
        input.throwOnStart = true
        let sink = QuestionSink(answer: "x")
        let controller = VoiceSessionController(input: input, synthesizer: MockSynthesizer(),
                                                onQuestion: sink.handle)
        await controller.startListening()
        if case .failed = controller.state {} else { Issue.record("expected .failed, got \(controller.state)") }
    }

    @Test func streamingSpeaksSentencesInOrder() async {
        let input = MockVoiceInput(final: "tell me a story")
        let synth = MockSynthesizer()
        let controller = VoiceSessionController(
            input: input, synthesizer: synth,
            onQuestion: { _ in nil },
            onQuestionStream: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield("Once upon a time.")
                    continuation.yield("Once upon a time. The end.")
                    continuation.yield("Once upon a time. The end. Bye now")
                    continuation.finish()
                }
            })

        await controller.startListening()
        await controller.finishAndAsk()

        #expect(synth.spokenTexts == ["Once upon a time.", "The end.", "Bye now"])
        #expect(controller.state == .idle)
    }

    @Test func bargeInDuringSpeakingStopsAndIdles() async {
        let input = MockVoiceInput(final: "question")
        let synth = MockSynthesizer(blockUntilStopped: true)
        let sink = QuestionSink(answer: "a long spoken answer")
        let controller = VoiceSessionController(input: input, synthesizer: synth, onQuestion: sink.handle)

        await controller.startListening()
        let task = Task { await controller.finishAndAsk() }
        for _ in 0..<50 where controller.state != .speaking { await Task.yield() }
        #expect(controller.state == .speaking)

        controller.bargeIn()
        await task.value
        #expect(synth.stopped)
        #expect(controller.state == .idle)
    }

    @Test func cancelDuringSpeakingStopsAndIdles() async {
        let input = MockVoiceInput(final: "question")
        let synth = MockSynthesizer(blockUntilStopped: true)
        let sink = QuestionSink(answer: "a long spoken answer")
        let controller = VoiceSessionController(input: input, synthesizer: synth, onQuestion: sink.handle)

        await controller.startListening()
        let task = Task { await controller.finishAndAsk() }
        for _ in 0..<50 where controller.state != .speaking { await Task.yield() }
        #expect(controller.state == .speaking)

        controller.cancel()
        await task.value
        #expect(synth.stopped)
        #expect(controller.state == .idle)
    }
}
