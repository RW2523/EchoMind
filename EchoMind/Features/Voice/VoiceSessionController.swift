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
    /// The user's finished utterance for the current turn (for the caption UI).
    private(set) var lastQuestion = ""
    /// The assistant's answer text as it's spoken, accumulated sentence-by-sentence
    /// (streaming) so the conversation view can caption what's being said.
    private(set) var spokenText = ""

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
    /// V3 hands-free barge-in: while the agent speaks, the mic stays open (echo
    /// cancellation on) and this task watches for the user starting to talk.
    private var bargeMonitorTask: Task<Void, Never>?
    private let onsetDetector = SpeechOnsetDetector()
    /// Set when a *spoken* interruption took over the mic, so the speaking teardown
    /// doesn't also stop the mic / start a second listen turn (avoids a double-start).
    private var voiceBargedIn = false

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
        lastQuestion = trimmed

        if let onQuestionStream {
            await speakStreaming(onQuestionStream(trimmed))
        } else {
            await speakOneShot(trimmed)
        }
    }

    private func speakOneShot(_ question: String) async {
        state = .thinking
        lastQuestion = question
        spokenText = ""
        let answer = await onQuestion(question)
        guard state == .thinking else { return }          // cancelled while thinking
        guard let answer, !answer.isEmpty else { state = .idle; return }

        state = .speaking
        spokenText = answer
        await synthesizer.speak(answer)
        guard state == .speaking else { return }          // cancelled while speaking
        state = .idle
    }

    /// V2: consume the cumulative answer stream on a producer task, chunk it into
    /// sentences, and speak them sequentially as they complete.
    private func speakStreaming(_ stream: AsyncThrowingStream<String, Error>) async {
        state = .thinking
        spokenText = ""
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
            spokenText += (spokenText.isEmpty ? "" : " ") + sentence   // caption
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
        voiceBargedIn = false
        endpointTimer?.cancel()
        endpointTimer = nil
        bargeMonitorTask?.cancel()
        bargeMonitorTask = nil
        listenTask?.cancel()
        answerTask?.cancel()
        sentenceContinuation?.finish()
        synthesizer.stop()
        let input = self.input
        Task { _ = await input.stop() }                   // best-effort STT teardown
        partialTranscript = ""
        lastQuestion = ""
        spokenText = ""
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

    /// User taps ✋ (or a spoken interruption is detected) while the agent is talking:
    /// stop TTS + generation and (hands-free) immediately open a fresh turn.
    func bargeIn() {
        guard state == .speaking || state == .thinking else { return }
        performBargeIn()
    }

    /// A spoken interruption detected by the hands-free barge monitor.
    private func handleVoiceBargeIn() {
        guard handsFree, state == .speaking || state == .thinking else { return }
        performBargeIn()
    }

    private func performBargeIn() {
        bargeMonitorTask?.cancel()
        bargeMonitorTask = nil
        answerTask?.cancel()
        sentenceContinuation?.finish()
        synthesizer.stop()
        state = .idle
        guard handsFree else { return }
        // The monitor (or the just-ended listen turn) still owns the mic; release it,
        // then open a clean turn. `voiceBargedIn` tells the speaking teardown to stand
        // down so we never start two capture sessions at once.
        voiceBargedIn = true
        Task { [weak self] in
            guard let self else { return }
            _ = await self.input.stop()
            await self.beginListenTurn()
        }
    }

    /// While the agent speaks hands-free, keep the mic open (echo cancellation on) and
    /// watch for the user starting to talk, so they can interrupt by voice — not only
    /// with the ✋ button. Fail-safe: any mic error just means no barge-in this turn.
    private func startBargeMonitor() async {
        guard handsFree else { return }
        voiceBargedIn = false
        // Open the mic up front (awaited) so ownership is deterministic: by the time we
        // speak — and later stop the monitor — start() has fully completed, so a normal
        // teardown can never race a half-started capture.
        let partials: AsyncStream<String>
        do { partials = try await input.start() } catch { return }   // no barge-in this turn
        let detector = onsetDetector
        bargeMonitorTask = Task { [weak self] in
            for await partial in partials {
                guard let self, !Task.isCancelled else { return }
                guard self.state == .speaking || self.state == .thinking else { return }
                if detector.detectedOnset(in: partial) {
                    self.handleVoiceBargeIn()
                    return
                }
            }
        }
    }

    /// Tear down the barge monitor after a hands-free answer finishes normally, and
    /// release its mic session so the next listen turn starts from a clean state.
    private func stopBargeMonitor() async {
        bargeMonitorTask?.cancel()
        bargeMonitorTask = nil
        if !voiceBargedIn { _ = await input.stop() }
    }

    private func beginListenTurn() async {
        guard handsFree else { return }
        endpointer.reset()
        partialTranscript = ""
        spokenText = ""        // clear the prior answer's caption as a new turn opens
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
        lastQuestion = trimmed
        // Keep the mic open through the answer so the user can interrupt by voice.
        await startBargeMonitor()
        if let onQuestionStream {
            await speakStreaming(onQuestionStream(trimmed))
        } else {
            await speakOneShot(trimmed)
        }
        await stopBargeMonitor()
        // If a spoken barge-in fired, it already owns the next turn — don't double-start.
        if handsFree, !voiceBargedIn, state == .idle { await beginListenTurn() }
    }
}
