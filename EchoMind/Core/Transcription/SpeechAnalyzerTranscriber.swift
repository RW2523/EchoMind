import Foundation
import Speech
import AVFoundation
import CoreMedia

/// TranscriptionService over the iOS 26 SpeechAnalyzer stack. All SpeechAnalyzer
/// types are confined to this file (§3.9) so API corrections touch one place.
/// Volatile vs. final is derived from the analyzer's `volatileRange`: a result
/// that no longer intersects the volatile window has been committed.
actor SpeechAnalyzerTranscriber: TranscriptionService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: BufferConverter?
    private var feedTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    func start(
        locale: Locale,
        audio: AsyncThrowingStream<AudioBufferBox, Error>
    ) async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])
        self.transcriber = transcriber

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.transcriberFailed("No compatible audio format for this locale.")
        }
        let converter = BufferConverter(targetFormat: format)
        self.converter = converter

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputBuilder = inputBuilder

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (updates, updatesContinuation) = AsyncThrowingStream<TranscriptionUpdate, Error>.makeStream()

        // Feed: convert each captured buffer to the analyzer's format and yield
        // it. Runs on the actor so the non-Sendable buffer never escapes — only
        // the Sendable AnalyzerInput is yielded into the input sequence.
        feedTask = Task { [weak self] in
            await self?.feedLoop(audio: audio)
        }

        // Results: map SpeechTranscriber results to TranscriptionUpdate.
        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    updatesContinuation.yield(await self.makeUpdate(from: result))
                }
                updatesContinuation.finish()
            } catch {
                updatesContinuation.finish(throwing: TranscriptionError.transcriberFailed(String(describing: error)))
            }
        }

        try await analyzer.start(inputSequence: inputSequence)
        return updates
    }

    func stop() async {
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        feedTask?.cancel()
        analyzer = nil
        transcriber = nil
        inputBuilder = nil
        converter = nil
    }

    // MARK: - Helpers

    private func feedLoop(audio: AsyncThrowingStream<AudioBufferBox, Error>) async {
        do {
            for try await box in audio {
                if let converted = try converter?.convert(box.buffer) {
                    inputBuilder?.yield(AnalyzerInput(buffer: converted))
                }
            }
        } catch {
            // Upstream audio stream ended or failed.
        }
        inputBuilder?.finish()
    }

    private func makeUpdate(from result: SpeechTranscriber.Result) async -> TranscriptionUpdate {
        let text = String(result.text.characters)
        let start = max(0, CMTimeGetSeconds(result.range.start))
        let end = max(start, CMTimeGetSeconds(result.range.end))
        let lower = start.isFinite ? start : 0
        let upper = end.isFinite ? end : lower

        let isFinal: Bool
        if let analyzer, let volatileRange = await analyzer.volatileRange {
            let intersection = CMTimeRangeGetIntersection(volatileRange, otherRange: result.range)
            isFinal = CMTimeGetSeconds(intersection.duration) <= 0
        } else {
            isFinal = true
        }
        return TranscriptionUpdate(text: text, isFinal: isFinal, audioRange: lower...upper)
    }
}
