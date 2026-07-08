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

        let buffers = try await audio.start()
        let updates: AsyncThrowingStream<TranscriptionUpdate, Error>
        do {
            updates = try await transcription.start(locale: locale, audio: buffers)
        } catch {
            await audio.stop()
            throw VoiceInputError.speechUnavailable
        }

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
        updateTask?.cancel()
        await transcription.stop()
        await audio.stop()
        continuation?.finish()
        continuation = nil
        return finalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
