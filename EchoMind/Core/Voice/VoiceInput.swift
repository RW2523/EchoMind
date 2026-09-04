import Foundation

/// Speech-to-text seam for the voice agent (V1). Reuses the existing on-device
/// transcription stack; the controller depends on this protocol so it stays
/// testable with a mock (mic capture is device-only). `start()` streams partial
/// transcripts for the live listening UI; `stop()` returns the final utterance.
@MainActor
protocol VoiceInput {
    func start() async throws -> AsyncStream<String>
    func stop() async -> String
}

nonisolated enum VoiceInputError: Error, Equatable {
    case microphoneDenied
    case speechUnavailable
    case startFailed
}

/// Live STT over `AudioCapturing` + `TranscriptionService` — the same pipeline the
/// live-transcript screen uses, scoped to a single spoken utterance.
@MainActor
final class LiveVoiceInput: VoiceInput {
    private let audio: any AudioCapturing
    private let transcription: any TranscriptionService
    private let permissions: any PermissionManaging
    private let assets: any SpeechAssetManaging
    private let locale: Locale

    private var finalized = ""
    private var volatile = ""
    private var updateTask: Task<Void, Never>?
    private var continuation: AsyncStream<String>.Continuation?
    /// True only between a fully successful start() and stop(). The audio and
    /// transcription actors are SHARED with the meeting recorder — stop() must
    /// never tear down a capture this voice session doesn't own (field bug:
    /// closing the voice screen killed an active meeting recording).
    private var owningCapture = false

    init(audio: any AudioCapturing,
         transcription: any TranscriptionService,
         permissions: any PermissionManaging,
         assets: any SpeechAssetManaging,
         locale: Locale = .current) {
        self.audio = audio
        self.transcription = transcription
        self.permissions = permissions
        self.assets = assets
        self.locale = locale
    }

    func start() async throws -> AsyncStream<String> {
        guard await permissions.requestMicrophone() == .granted,
              await permissions.requestSpeech() == .granted else {
            throw VoiceInputError.microphoneDenied
        }
        finalized = ""
        volatile = ""

        // V3: echo cancellation so the mic doesn't transcribe the agent's own TTS.
        await audio.setVoiceProcessing(true)
        let buffers = try await audio.start()
        let updates: AsyncThrowingStream<TranscriptionUpdate, Error>
        do {
            updates = try await transcription.start(locale: locale, audio: buffers)
        } catch {
            await audio.stop()
            throw VoiceInputError.speechUnavailable
        }

        owningCapture = true
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.continuation = continuation
        updateTask = Task { @MainActor [weak self] in
            do {
                for try await update in updates {
                    self?.apply(update, yieldingTo: continuation)
                }
            } catch {
                // Transcription ended or failed; stop() finishes the stream.
            }
        }
        return stream
    }

    private func apply(_ update: TranscriptionUpdate,
                       yieldingTo continuation: AsyncStream<String>.Continuation) {
        if update.isFinal {
            finalized += (finalized.isEmpty ? "" : " ") + update.text
            volatile = ""
        } else {
            volatile = update.text
        }
        let combined = (finalized + " " + volatile).trimmingCharacters(in: .whitespaces)
        continuation.yield(combined)
    }

    func stop() async -> String {
        // Only tear down a capture this session actually started — the actors
        // are shared with the meeting recorder.
        if owningCapture {
            owningCapture = false
            // Stop the transcriber FIRST and let its finalize flush the tail of
            // the utterance through the update loop; cancelling the consumer
            // before the flush dropped the last words of voice questions. The
            // finished updates stream ends the loop, so await it (don't cancel).
            await transcription.stop()
            await updateTask?.value
            await audio.stop()
        }
        updateTask?.cancel()
        updateTask = nil
        continuation?.finish()
        continuation = nil
        return finalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
