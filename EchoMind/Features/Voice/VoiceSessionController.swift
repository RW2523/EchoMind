import Foundation

/// Orchestrates one push-to-talk voice turn (Voice Agent V1): listen → think →
/// speak, cancellable from any state. Decoupled from RAG/chat via `onQuestion`
/// (given the final utterance, returns the answer text to speak, or nil), so the
/// whole state machine is unit-testable with mocks. STT is `VoiceInput`, TTS is
/// `SpeechSynthesizing`. Streaming + barge-in arrive in V2/V3 on this same object.
@MainActor
@Observable
final class VoiceSessionController {
    nonisolated enum State: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var partialTranscript = ""

    private let input: any VoiceInput
    private let synthesizer: any SpeechSynthesizing
    private let onQuestion: (String) async -> String?
    /// V2: streaming answer producer. When set, the answer is spoken
    /// sentence-by-sentence as it generates; otherwise the whole answer is spoken.
    private let onQuestionStream: ((String) -> AsyncThrowingStream<String, Error>)?

    private let now: @Sendable () -> TimeInterval

    private var listenTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?
    private var sentenceContinuation: AsyncStream<String>.Continuation?
    private var endpointTimer: Task<Void, Never>?
    private var handsFree = false
    private var endpointer = TurnEndpointer()

    init(input: any VoiceInput,
         synthesizer: any SpeechSynthesizing,
         onQuestion: @escaping (String) async -> String?,
         onQuestionStream: ((String) -> AsyncThrowingStream<String, Error>)? = nil,
         now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.input = input
        self.synthesizer = synthesizer
        self.onQuestion = onQuestion
        self.onQuestionStream = onQuestionStream
        self.now = now
    }

    var isActive: Bool { state != .idle }
    var canSpeak: Bool { synthesizer.isAvailable }
    var isHandsFree: Bool { handsFree }

    /// Begin capturing speech and streaming partial transcripts to the UI.
    func startListening() async {
        guard state == .idle else { return }
        partialTranscript = ""
        do {
            let partials = try await input.start()
            state = .listening
            listenTask = Task { [weak self] in
                for await partial in partials {
                    self?.partialTranscript = partial
                }
            }
        } catch {
            state = .failed("Couldn't start listening. Check microphone access.")
        }
    }

    /// Stop listening, run the question, and speak the answer — streaming
    /// sentence-by-sentence when a streaming producer is available.
    func finishAndAsk() async {
        guard state == .listening else { return }
        listenTask?.cancel()
        let question = await input.stop()
        partialTranscript = ""
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }

        if let onQuestionStream {
            await speakStreaming(onQuestionStream(trimmed))
        } else {
            await speakOneShot(trimmed)
        }
    }

    private func speakOneShot(_ question: String) async {
        state = .thinking
        let answer = await onQuestion(question)
        guard state == .thinking else { return }          // cancelled while thinking
        guard let answer, !answer.isEmpty else { state = .idle; return }

        state = .speaking
        await synthesizer.speak(answer)
        guard state == .speaking else { return }          // cancelled while speaking
        state = .idle
    }

    /// V2: consume the cumulative answer stream on a producer task, chunk it into
    /// sentences, and speak them sequentially as they complete.
    private func speakStreaming(_ stream: AsyncThrowingStream<String, Error>) async {
        state = .thinking
        let (sentences, continuation) = AsyncStream<String>.makeStream()
        sentenceContinuation = continuation
        answerTask = Task {
            var chunker = SentenceChunker()
            do {
                for try await cumulative in stream {
                    for sentence in chunker.push(cumulative: cumulative) { continuation.yield(sentence) }
                }
            } catch {}
            if let tail = chunker.flush() { continuation.yield(tail) }
            continuation.finish()
        }

        for await sentence in sentences {
            if state == .thinking { state = .speaking }
            guard state == .speaking else { break }       // cancelled
            await synthesizer.speak(sentence)
        }
        answerTask = nil
        sentenceContinuation = nil
        guard state == .speaking || state == .thinking else { return }
        state = .idle
    }

    /// Barge-out / abort from any state: stop STT + TTS + generation and reset.
    func cancel() {
        handsFree = false
        endpointTimer?.cancel()
        endpointTimer = nil
        listenTask?.cancel()
        answerTask?.cancel()
        sentenceContinuation?.finish()
        synthesizer.stop()
        let input = self.input
        Task { _ = await input.stop() }                   // best-effort STT teardown
        partialTranscript = ""
        state = .idle
    }

    // MARK: - Hands-free (V3)

    /// Enter continuous conversation: listen → auto-endpoint → answer → listen …
    func startConversation() async {
        guard state == .idle else { return }
        handsFree = true
        await beginListenTurn()
    }

    func stopConversation() { cancel() }

    /// User starts speaking while the agent is talking: stop TTS + generation and
    /// (hands-free) immediately open a fresh turn.
    func bargeIn() {
        guard state == .speaking || state == .thinking else { return }
        answerTask?.cancel()
        sentenceContinuation?.finish()
        synthesizer.stop()
        state = .idle
        if handsFree { Task { await beginListenTurn() } }
    }

    private func beginListenTurn() async {
        guard handsFree else { return }
        endpointer.reset()
        partialTranscript = ""
        do {
            let partials = try await input.start()
            state = .listening
            listenTask = Task { [weak self] in
                for await partial in partials {
                    guard let self else { return }
                    self.partialTranscript = partial
                    self.endpointer.update(transcript: partial, now: self.now())
                }
            }
            startEndpointTimer()
        } catch {
            state = .failed("Couldn't start listening. Check microphone access.")
            handsFree = false
        }
    }

    private func startEndpointTimer() {
        endpointTimer?.cancel()
        endpointTimer = Task { [weak self] in
            while true {
                guard let self, self.handsFree, self.state == .listening else { return }
                if self.endpointer.shouldEndTurn(now: self.now()) {
                    self.endpointTimer = nil
                    await self.autoFinishTurn()
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func autoFinishTurn() async {
        guard state == .listening else { return }
        listenTask?.cancel()
        let question = await input.stop()
        partialTranscript = ""
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if handsFree { await beginListenTurn() } else { state = .idle }
            return
        }
        if let onQuestionStream {
            await speakStreaming(onQuestionStream(trimmed))
        } else {
            await speakOneShot(trimmed)
        }
        if handsFree, state == .idle { await beginListenTurn() }
    }
}
