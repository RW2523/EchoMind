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

/// Yields a different scripted partial stream on each `start()`, so a test can drive
/// the listening turn and the hands-free barge monitor independently.
@MainActor
private final class ScriptedVoiceInput: VoiceInput {
    let scripts: [(partials: [String], final: String)]
    private(set) var startCount = 0

    init(_ scripts: [(partials: [String], final: String)]) { self.scripts = scripts }

    func start() async throws -> AsyncStream<String> {
        let idx = startCount
        startCount += 1
        let script = idx < scripts.count ? scripts[idx] : (partials: [], final: "")
        return AsyncStream { continuation in
            for partial in script.partials { continuation.yield(partial) }
            continuation.finish()
        }
    }

    func stop() async -> String {
        let idx = max(0, startCount - 1)
        return idx < scripts.count ? scripts[idx].final : ""
    }
}

/// Monotonic clock: each read advances 1s, so the endpointer's quiescence window
/// elapses on the next poll without waiting real time.
private final class AdvancingClock: @unchecked Sendable {
    private var t: TimeInterval = 0
    func next() -> TimeInterval { t += 1; return t }
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

    @Test func captionsSurfaceQuestionAndStreamedAnswer() async {
        let input = MockVoiceInput(final: "tell me a story")
        let synth = MockSynthesizer()
        let controller = VoiceSessionController(
            input: input, synthesizer: synth,
            onQuestion: { _ in nil },
            onQuestionStream: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield("Once upon a time.")
                    continuation.yield("Once upon a time. The end.")
                    continuation.finish()
                }
            })

        await controller.startListening()
        await controller.finishAndAsk()

        #expect(controller.lastQuestion == "tell me a story")
        #expect(controller.spokenText == "Once upon a time. The end.")   // captions accumulate
    }

    @Test func cancelClearsCaptions() async {
        let input = MockVoiceInput(final: "hello there")
        let synth = MockSynthesizer()
        let sink = QuestionSink(answer: "hi back")
        let controller = VoiceSessionController(input: input, synthesizer: synth, onQuestion: sink.handle)

        await controller.startListening()
        await controller.finishAndAsk()
        #expect(!controller.spokenText.isEmpty)

        controller.cancel()
        #expect(controller.spokenText.isEmpty)
        #expect(controller.lastQuestion.isEmpty)
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

    @Test func handsFreeSpokenBargeInStopsAgentAndReopensTurn() async {
        // Turn 1 = listening ("what is the plan"); turn 2 = the barge monitor, which
        // hears the user start talking again ("wait stop now") while the agent answers;
        // later turns are quiet so the reopened listen turn just waits.
        let input = ScriptedVoiceInput([
            (["what is the plan"], "what is the plan"),
            (["wait stop now"], "wait stop now"),
            ([], ""), ([], ""),
        ])
        let synth = MockSynthesizer(blockUntilStopped: true)
        let sink = QuestionSink(answer: "here is the whole plan spoken slowly")
        let clock = AdvancingClock()
        let controller = VoiceSessionController(
            input: input, synthesizer: synth, onQuestion: sink.handle,
            now: { clock.next() })

        await controller.startConversation()

        // Wait for the monitor to fire a barge-in: the agent is stopped and a fresh
        // listen turn is opened (a 3rd capture session). Bounded so it can't hang.
        var reopened = false
        for _ in 0..<400 {
            if synth.stopped && input.startCount >= 3 { reopened = true; break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(reopened)
        #expect(synth.stopped)                 // TTS/generation cut off by the interruption
        #expect(controller.state == .listening)  // hands-free reopened a turn
        controller.cancel()
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
