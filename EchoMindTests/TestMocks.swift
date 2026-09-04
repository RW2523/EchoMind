import Foundation
import AVFoundation
@testable import EchoMind

/// Emits no buffers; drives the transcription mock independently.
actor MockAudioCapturing: AudioCapturing {
    nonisolated let events: AsyncStream<AudioEngineEvent>
    private let eventContinuation: AsyncStream<AudioEngineEvent>.Continuation

    init() {
        (events, eventContinuation) = AsyncStream<AudioEngineEvent>.makeStream()
    }

    func start() async throws -> AsyncThrowingStream<AudioBufferBox, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func stop() async {
        eventContinuation.finish()
    }
}

/// Replays a fixed list of updates, then finishes the stream.
nonisolated final class MockTranscriptionService: TranscriptionService, @unchecked Sendable {
    let updates: [TranscriptionUpdate]
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?

    init(updates: [TranscriptionUpdate]) { self.updates = updates }

    func start(locale: Locale,
               audio: AsyncThrowingStream<AudioBufferBox, Error>) async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        let updates = self.updates
        return AsyncThrowingStream { continuation in
            for update in updates { continuation.yield(update) }
            // Stay open until stop(), like the real SpeechAnalyzer stream — a
            // stream that finishes mid-recording reads as a dead pipeline.
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func stop() async {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

nonisolated struct MockEmbeddingService: EmbeddingService {
    let dim: Int
    let map: @Sendable (String) -> [Float]

    var dimension: Int { get async throws { dim } }
    func embed(_ texts: [String]) async throws -> [[Float]] { texts.map(map) }
    func prepareAssets() async throws {}
}

nonisolated struct StubSpeechAssetManager: SpeechAssetManaging {
    var configuredStatus: SpeechAssetStatus = .installed

    func status(for locale: Locale) async throws -> SpeechAssetStatus { configuredStatus }

    func ensureInstalled(for locale: Locale) -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(1.0)
            continuation.finish()
        }
    }
}
