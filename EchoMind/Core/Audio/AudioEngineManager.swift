import Foundation
import AVFoundation

/// Owns the audio capture stack (§3.2). One capture at a time; nothing arms
/// audio at launch. Emits UI events on `events` and PCM buffers from `start()`.
protocol AudioCapturing: Actor {
    nonisolated var events: AsyncStream<AudioEngineEvent> { get }
    func start() async throws -> AsyncThrowingStream<AudioBufferBox, Error>
    func stop() async
    /// V3: enable hardware echo cancellation before the next `start()` (voice agent).
    func setVoiceProcessing(_ enabled: Bool)
}

extension AudioCapturing {
    func setVoiceProcessing(_ enabled: Bool) {}   // default: no-op (plain capture / mocks)
}

actor AudioEngineManager: AudioCapturing {
    nonisolated let events: AsyncStream<AudioEngineEvent>
    private let eventContinuation: AsyncStream<AudioEngineEvent>.Continuation

    private let configurator: any AudioSessionConfiguring
    private let levelMeter = AudioLevelMeter()
    private let stateMachine = AudioInterruptionStateMachine()

    private var engine: AVAudioEngine?
    private var bufferContinuation: AsyncThrowingStream<AudioBufferBox, Error>.Continuation?
    private var state: RecordingState = .idle
    private var observerTokens: [NSObjectProtocol] = []

    private var accumulatedActive: TimeInterval = 0
    private var segmentStart: Date?
    private var elapsedTask: Task<Void, Never>?
    /// V3: hardware echo cancellation for the voice agent (mic doesn't hear TTS as
    /// user speech — required for barge-in). Off for plain recording.
    private var voiceProcessingEnabled = false

    /// Toggle echo cancellation before the next `start()`. Best-effort per §voice.
    func setVoiceProcessing(_ enabled: Bool) { voiceProcessingEnabled = enabled }

    init(configurator: any AudioSessionConfiguring = AudioSessionConfigurator()) {
        self.configurator = configurator
        let (stream, continuation) = AsyncStream<AudioEngineEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.events = stream
        self.eventContinuation = continuation
    }

    // MARK: - Lifecycle

    /// NOTE (§7.3): capture lifetime belongs to this actor / app scope, NOT to
    /// any view. Recording must survive view disappearance (background capture
    /// is a core feature) — only `stop()` or an unrecoverable interruption ends
    /// it. Do not tie start/stop to a view's `.task`/`onDisappear`.
    func start() async throws -> AsyncThrowingStream<AudioBufferBox, Error> {
        guard state == .idle else { throw AudioCaptureError.alreadyCapturing }
        do {
            try configurator.activate()
        } catch {
            throw AudioCaptureError.sessionConfigurationFailed(error.localizedDescription)
        }

        let engine = AVAudioEngine()
        self.engine = engine
        // Enable voice-processing (AEC) on the I/O nodes before the graph starts.
        if voiceProcessingEnabled {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                try engine.outputNode.setVoiceProcessingEnabled(true)
            } catch {
                // Voice processing isn't supported here — carry on with plain capture
                // rather than risk an invalid input format below.
            }
            // Enabling voice processing can leave the input node momentarily without a
            // valid format; installing a tap on a 0 Hz / 0-channel node raises an
            // NSException that aborts the whole app. If that happened, back it out.
            let vpFormat = engine.inputNode.outputFormat(forBus: 0)
            if vpFormat.sampleRate <= 0 || vpFormat.channelCount == 0 {
                try? engine.inputNode.setVoiceProcessingEnabled(false)
                try? engine.outputNode.setVoiceProcessingEnabled(false)
            }
        }
        let (stream, continuation) = AsyncThrowingStream<AudioBufferBox, Error>.makeStream(bufferingPolicy: .unbounded)
        self.bufferContinuation = continuation

        engine.prepare()          // settle the input format before tapping
        do {
            try installTap(on: engine)
            try engine.start()
        } catch {
            let message = (error as? AudioCaptureError).map { "\($0)" } ?? error.localizedDescription
            continuation.finish(throwing: AudioCaptureError.engineStartFailed(message))
            self.engine = nil
            self.bufferContinuation = nil
            try? configurator.deactivate()
            throw AudioCaptureError.engineStartFailed(message)
        }

        state = .recording
        accumulatedActive = 0
        segmentStart = Date()
        registerObservers()
        startElapsedTicker()
        emit(.stateChanged(.recording))
        emitInputFormat(engine)
        return stream
    }

    func stop() async {
        guard state != .idle else { return }
        removeObservers()
        elapsedTask?.cancel()
        elapsedTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        bufferContinuation?.finish()
        bufferContinuation = nil
        pauseElapsed()
        try? configurator.deactivate()
        state = .idle
        emit(.stateChanged(.idle))
    }

    // MARK: - Tap

    private func installTap(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A 0 Hz / 0-channel format means the mic isn't usable (no input route, or
        // voice processing left the node invalid). `installTap` with such a format
        // raises an NSException that can't be caught in Swift and aborts the app —
        // so refuse up front and surface a normal error the caller already handles.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.engineStartFailed("No usable audio input format.")
        }
        let bufferCont = bufferContinuation
        let eventCont = eventContinuation
        let meter = levelMeter
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            // Audio-thread hot path: only yield + meter, no allocation, no actor hop.
            bufferCont?.yield(AudioBufferBox(buffer))
            eventCont.yield(.level(meter.level(for: buffer)))
        }
    }

    private func reinstallTap() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        try? installTap(on: engine)
        emitInputFormat(engine)
    }

    private func rebuildEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        let fresh = AVAudioEngine()
        engine = fresh
        try? configurator.activate()
        fresh.prepare()
        guard (try? installTap(on: fresh)) != nil else { return }
        try? fresh.start()
        emitInputFormat(fresh)
        emit(.stateChanged(state))
    }

    // MARK: - Session events

    private func apply(_ event: AudioSessionEvent) {
        for command in stateMachine.handle(event, while: state) {
            execute(command)
        }
    }

    private func execute(_ command: AudioCommand) {
        switch command {
        case .pauseCapture:
            engine?.pause()
            pauseElapsed()
            state = .pausedByInterruption
            emit(.stateChanged(.pausedByInterruption))
        case .surfacePausedState:
            state = .pausedByInterruption
            emit(.stateChanged(.pausedByInterruption))
        case .resumeCapture:
            resumeCapture()
        case .reinstallTap:
            reinstallTap()
        case .rebuildEngine:
            rebuildEngine()
        }
    }

    private func resumeCapture() {
        do {
            try configurator.activate()
            try engine?.start()
            resumeElapsed()
            state = .recording
            emit(.stateChanged(.recording))
        } catch {
            // One retry; if it still fails, stay paused with a manual Resume path.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self?.retryResume()
            }
        }
    }

    private func retryResume() {
        do {
            try configurator.activate()
            try engine?.start()
            resumeElapsed()
            state = .recording
            emit(.stateChanged(.recording))
        } catch {
            state = .pausedByInterruption
            emit(.stateChanged(.pausedByInterruption))
        }
    }

    // MARK: - Elapsed

    private func startElapsedTicker() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.emitElapsed()
            }
        }
    }

    private func emitElapsed() { emit(.elapsed(currentElapsed())) }

    private func currentElapsed() -> TimeInterval {
        if let segmentStart, state == .recording {
            return accumulatedActive + Date().timeIntervalSince(segmentStart)
        }
        return accumulatedActive
    }

    private func pauseElapsed() {
        if let segmentStart {
            accumulatedActive += Date().timeIntervalSince(segmentStart)
            self.segmentStart = nil
        }
    }

    private func resumeElapsed() { segmentStart = Date() }

    // MARK: - Observers

    private func registerObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observerTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: nil
        ) { [weak self] note in
            guard let event = AudioEngineManager.interruptionEvent(from: note) else { return }
            Task { await self?.apply(event) }
        })
        observerTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: nil
        ) { [weak self] note in
            guard let event = AudioEngineManager.routeEvent(from: note) else { return }
            Task { await self?.apply(event) }
        })
        observerTokens.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil
        ) { [weak self] _ in
            Task { await self?.apply(.mediaServicesReset) }
        })
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observerTokens.forEach(center.removeObserver)
        observerTokens.removeAll()
    }

    // MARK: - Emit + notification parsing

    private func emit(_ event: AudioEngineEvent) { eventContinuation.yield(event) }

    private func emitInputFormat(_ engine: AVAudioEngine) {
        let format = engine.inputNode.outputFormat(forBus: 0)
        emit(.inputFormatChanged(sampleRate: format.sampleRate, channels: format.channelCount))
    }

    nonisolated static func interruptionEvent(from note: Notification) -> AudioSessionEvent? {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    nonisolated static func routeEvent(from note: Notification) -> AudioSessionEvent? {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return nil }
        return .routeChanged(reason: reason)
    }
}
