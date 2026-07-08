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

    private var listenTask: Task<Void, Never>?

    init(input: any VoiceInput,
         synthesizer: any SpeechSynthesizing,
         onQuestion: @escaping (String) async -> String?) {
        self.input = input
        self.synthesizer = synthesizer
        self.onQuestion = onQuestion
    }

    var isActive: Bool { state != .idle }
    var canSpeak: Bool { synthesizer.isAvailable }

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

    /// Stop listening, run the question through `onQuestion`, and speak the answer.
    func finishAndAsk() async {
        guard state == .listening else { return }
        listenTask?.cancel()
        let question = await input.stop()
        partialTranscript = ""
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return }

        state = .thinking
        let answer = await onQuestion(trimmed)
        guard state == .thinking else { return }          // cancelled while thinking
        guard let answer, !answer.isEmpty else { state = .idle; return }

        state = .speaking
        await synthesizer.speak(answer)
        guard state == .speaking else { return }          // cancelled while speaking
        state = .idle
    }

    /// Barge-out / abort from any state: stop STT + TTS and reset.
    func cancel() {
        listenTask?.cancel()
        synthesizer.stop()
        let input = self.input
        Task { _ = await input.stop() }                   // best-effort STT teardown
        partialTranscript = ""
        state = .idle
    }
}
