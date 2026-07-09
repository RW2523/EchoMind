import Foundation

@MainActor
@Observable
final class SessionDetailViewModel {
    enum SummaryState: Equatable {
        case none
        case generating(SummarizerProgress)
        case available(MeetingSummary)
        case failed(String)
        case requiresAppleIntelligence(AvailabilityStatus.TierBReason)
    }

    private(set) var session: SessionSnapshot
    private(set) var segments: [SegmentSnapshot] = []
    private(set) var summaryState: SummaryState = .none
    private(set) var isIdentifyingSpeakers = false
    private(set) var actionStates: [Bool] = []
    var draftTitle: String

    private let repository: any SessionRepository
    private let summarizer: any SummarizerService
    private let availability: any AvailabilityProviding
    private let audioStore: AudioStore
    private let diarizer: any DiarizationService
    private let reportGenerator: (any ReportGenerating)?
    private var pendingWatcher: Task<Void, Never>?

    init(session: SessionSnapshot,
         repository: any SessionRepository,
         summarizer: any SummarizerService,
         availability: any AvailabilityProviding,
         audioStore: AudioStore = AudioStore(),
         diarizer: any DiarizationService = UnavailableDiarizationService(),
         reportGenerator: (any ReportGenerating)? = nil) {
        self.session = session
        self.draftTitle = session.title
        self.repository = repository
        self.summarizer = summarizer
        self.availability = availability
        self.reportGenerator = reportGenerator
        self.audioStore = audioStore
        self.diarizer = diarizer
    }

    /// Whether "Identify speakers" should be offered: engine linked + audio on disk.
    var canIdentifySpeakers: Bool {
        diarizer.isAvailable && audioStore.exists(session.id)
    }

    /// M3: run diarization on the retained audio and persist speaker labels onto
    /// each transcript segment (by max temporal overlap), then reload.
    func identifySpeakers() async {
        guard canIdentifySpeakers, !isIdentifyingSpeakers else { return }
        isIdentifyingSpeakers = true
        defer { isIdentifyingSpeakers = false }
        do {
            let result = try await diarizer.diarize(audioURL: audioStore.url(for: session.id))
            guard !result.isEmpty else { return }
            let spans = segments.map {
                SpeakerLabeler.Span(id: $0.id, start: $0.startTime, end: $0.endTime)
            }
            let labels = SpeakerLabeler.assign(transcript: spans, diarization: result.segments)
            guard !labels.isEmpty else { return }
            try await repository.setSpeakerLabels(labels, sessionId: session.id)
            await load()
        } catch {
            // Best-effort: leave labels as-is on failure.
        }
    }

    private var isManuallyGenerating = false

    func load() async {
        if let fresh = try? await repository.fetchSession(id: session.id) { session = fresh }
        segments = (try? await repository.fetchSegments(sessionId: session.id)) ?? []
        actionStates = normalizedActionStates()
        refreshSummaryState()
        watchPendingReportIfNeeded()
    }

    func refreshSummaryState() {
        if isManuallyGenerating { return }
        if let summary = currentSummary() {
            summaryState = .available(summary)
            return
        }
        switch session.reportState {
        case .pending:
            summaryState = .generating(.reducing)
        case .failed:
            summaryState = .failed("The report didn't finish generating.")
        case .none, .ready, .unavailable:
            switch availability.status {
            case .tierA: summaryState = .none
            case .tierB(let reason): summaryState = .requiresAppleIntelligence(reason)
            }
        }
    }

    /// R1: while a report is generating in the background, poll for completion so
    /// the detail updates without any user action.
    private func watchPendingReportIfNeeded() {
        guard session.reportState == .pending, session.summaryJSON == nil else { return }
        pendingWatcher?.cancel()
        pendingWatcher = Task { [weak self] in
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(1200))
                guard let self, !self.isManuallyGenerating else { return }
                guard let fresh = try? await self.repository.fetchSession(id: self.session.id) else { continue }
                if fresh.reportState != .pending || fresh.summaryJSON != nil {
                    self.session = fresh
                    self.actionStates = self.normalizedActionStates()
                    self.refreshSummaryState()
                    return
                }
            }
        }
    }

    private func currentSummary() -> MeetingSummary? {
        guard let json = session.summaryJSON,
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: Data(json.utf8)) else { return nil }
        return summary
    }

    private func normalizedActionStates() -> [Bool] {
        let count = currentSummary()?.actionItems.count ?? 0
        var states = session.actionStates
        if states.count < count { states += Array(repeating: false, count: count - states.count) }
        else if states.count > count { states = Array(states.prefix(count)) }
        return states
    }

    /// Toggle an action item's completion and persist it (user state, not model output).
    func toggleAction(_ index: Int) {
        guard index >= 0, index < actionStates.count else { return }
        actionStates[index].toggle()
        let json = (try? String(decoding: JSONEncoder().encode(actionStates), as: UTF8.self)) ?? "[]"
        let id = session.id
        Task { try? await repository.setActionStates(json, sessionId: id) }
    }

    func generateSummary() async {
        let snapshots = segments.map {
            SegmentText(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
        }
        let previous = summaryState
        isManuallyGenerating = true
        summaryState = .generating(.planning)
        defer { isManuallyGenerating = false }
        do {
            let summary = try await summarizer.summarize(segments: snapshots) { [weak self] progress in
                Task { @MainActor in
                    if case .generating = self?.summaryState { self?.summaryState = .generating(progress) }
                }
            }
            let json = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
            try? await repository.setReport(summaryJSON: json, sessionId: session.id)
            session.summaryJSON = json
            session.reportState = .ready
            actionStates = normalizedActionStates()
            summaryState = .available(summary)
        } catch is CancellationError {
            summaryState = previous
        } catch SummarizerError.notEnoughContent {
            summaryState = .failed("Not enough transcript to summarize.")
        } catch SummarizerError.tooLong {
            summaryState = .failed("This session is too long to summarize.")
        } catch {
            try? await repository.setReportState(.failed, sessionId: session.id)
            summaryState = .failed("Couldn't summarize this content.")
        }
    }

    func commitRename() async {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { draftTitle = session.title; return }
        try? await repository.rename(sessionID: session.id, to: trimmed)
        session.title = trimmed
    }

    func delete() async {
        try? await repository.delete(id: session.id)
        audioStore.remove(session.id)   // P17: drop the retained recording too
    }

    var markdownExport: SessionExport {
        SessionExport(fileName: SessionExporter.sanitizedFileName(session.title, ext: "md"),
                      contents: SessionExporter.markdown(session: session, segments: segments))
    }

    var textExport: SessionExport {
        SessionExport(fileName: SessionExporter.sanitizedFileName(session.title, ext: "txt"),
                      contents: SessionExporter.plainText(session: session, segments: segments))
    }
}
