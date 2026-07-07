import Foundation

/// Orchestrates permissions → assets → session insert → audio + transcription,
/// mirrors the manager's elapsed/level events, and persists each finalized
/// segment incrementally (§3.4/§3.5). Owns persistence so Core/Transcription
/// stays storage-free.
@MainActor
@Observable
final class LiveTranscriptViewModel {
    enum Phase: Equatable {
        case idle
        case preparingAssets(progress: Double)
        case recording
        case pausedByInterruption
        case stopping
        case failed(TranscriptionError)
    }

    struct TranscriptLine: Identifiable, Equatable, Sendable {
        let id: UUID
        let text: String
        let start: TimeInterval
        let end: TimeInterval
    }

    private(set) var phase: Phase = .idle {
        didSet {
            #if DEBUG
            if case .failed(let error) = phase { print("[LiveTranscript] failed: \(error)") }
            #endif
        }
    }
    private(set) var finalizedLines: [TranscriptLine] = []
    private(set) var volatileText: String = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0

    private let audio: any AudioCapturing
    private let transcription: any TranscriptionService
    private let assets: any SpeechAssetManaging
    private let sessions: any SessionRepository
    private let permissions: any PermissionManaging
    private let indexer: (any IndexerService)?
    private let locale: Locale

    private var sessionId: UUID?
    private var startedAt: Date?
    private var eventTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    init(audio: any AudioCapturing,
         transcription: any TranscriptionService,
         assets: any SpeechAssetManaging,
         sessions: any SessionRepository,
         permissions: any PermissionManaging,
         indexer: (any IndexerService)? = nil,
         locale: Locale = .current) {
        self.audio = audio
        self.transcription = transcription
        self.assets = assets
        self.sessions = sessions
        self.permissions = permissions
        self.indexer = indexer
        self.locale = locale
    }

    var isRecording: Bool { phase == .recording || phase == .pausedByInterruption }

    /// DEBUG-only: the active session id, so the segment inspector can query
    /// persisted segments live during recording (§3.1).
    var activeSessionId: UUID? { sessionId }

    // MARK: - Start

    func startTapped() async {
        switch phase {
        case .idle, .failed: break
        default: return
        }

        guard await ensurePermissions(), await ensureAssets() else { return }
        guard StorageGuard.hasSufficientSpace() else {
            phase = .failed(.insufficientStorage)
            return
        }

        let id = UUID()
        let started = Date()
        do {
            try await sessions.create(SessionSnapshot(id: id, title: "Recording…",
                                                      createdAt: started, updatedAt: started,
                                                      origin: .live))
        } catch {
            phase = .failed(.transcriberFailed("Couldn't create the session."))
            return
        }
        sessionId = id
        startedAt = started
        finalizedLines = []
        volatileText = ""
        elapsed = 0
        level = 0

        do {
            let buffers = try await audio.start()
            let updates = try await transcription.start(locale: locale, audio: buffers)
            startEventLoop()
            startUpdateLoop(updates)
            phase = .recording
        } catch is AudioCaptureError {
            phase = .failed(.sessionActivationFailed)
        } catch let error as TranscriptionError {
            phase = .failed(error)
        } catch {
            phase = .failed(.transcriberFailed(String(describing: error)))
        }
    }

    private func ensurePermissions() async -> Bool {
        if await permissions.requestMicrophone() != .granted {
            phase = .failed(.microphoneDenied)
            return false
        }
        if await permissions.requestSpeech() != .granted {
            phase = .failed(.speechDenied)
            return false
        }
        return true
    }

    private func ensureAssets() async -> Bool {
        do {
            switch try await assets.status(for: locale) {
            case .installed:
                return true
            case .unsupportedLocale:
                phase = .failed(.localeUnsupported(locale.identifier))
                return false
            case .needsDownload:
                phase = .preparingAssets(progress: 0)
                for try await progress in assets.ensureInstalled(for: locale) {
                    phase = .preparingAssets(progress: progress)
                }
                return true
            }
        } catch {
            phase = .failed(.assetDownloadFailed(String(describing: error)))
            return false
        }
    }

    // MARK: - Streams

    private func startEventLoop() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.audio.events {
                self.handle(event)
            }
        }
    }

    private func handle(_ event: AudioEngineEvent) {
        switch event {
        case .level(let value):
            level = value
        case .elapsed(let value):
            elapsed = value
        case .stateChanged(let state):
            switch state {
            case .recording where phase == .pausedByInterruption:
                phase = .recording
            case .pausedByInterruption where phase == .recording:
                phase = .pausedByInterruption
            default:
                break
            }
        case .inputFormatChanged:
            break
        }
    }

    private func startUpdateLoop(_ updates: AsyncThrowingStream<TranscriptionUpdate, Error>) {
        updateTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await update in updates {
                    await self.handle(update)
                }
            } catch {
                self.phase = .failed(.transcriberFailed(String(describing: error)))
                await self.finalize()
            }
        }
    }

    private func handle(_ update: TranscriptionUpdate) async {
        guard update.isFinal else {
            volatileText = update.text
            return
        }
        let line = TranscriptLine(id: UUID(), text: update.text,
                                  start: update.audioRange.lowerBound, end: update.audioRange.upperBound)
        finalizedLines.append(line)
        volatileText = ""
        if let sessionId {
            try? await sessions.appendSegment(
                SegmentSnapshot(id: line.id, sessionId: sessionId, text: line.text,
                                startTime: line.start, endTime: line.end),
                toSession: sessionId)
        }
    }

    // MARK: - Stop

    func stopTapped() async {
        guard isRecording else { return }
        phase = .stopping
        await transcription.stop()
        await audio.stop()
        eventTask?.cancel()
        updateTask?.cancel()
        await finalize()
        if let indexer, let id = sessionId {
            Task { [indexer] in try? await indexer.indexSession(id: id) }
        }
        phase = .idle
    }

    private func finalize() async {
        guard let sessionId, let startedAt else { return }
        try? await sessions.update(
            SessionSnapshot(id: sessionId, title: Self.defaultTitle(startedAt),
                            createdAt: startedAt, updatedAt: Date(), duration: elapsed, origin: .live))
    }

    static func defaultTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Meeting \(formatter.string(from: date))"
    }
}
