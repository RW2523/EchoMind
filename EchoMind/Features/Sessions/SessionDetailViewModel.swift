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
    var draftTitle: String

    private let repository: any SessionRepository
    private let summarizer: any SummarizerService
    private let availability: any AvailabilityProviding

    init(session: SessionSnapshot,
         repository: any SessionRepository,
         summarizer: any SummarizerService,
         availability: any AvailabilityProviding) {
        self.session = session
        self.draftTitle = session.title
        self.repository = repository
        self.summarizer = summarizer
        self.availability = availability
    }

    func load() async {
        segments = (try? await repository.fetchSegments(sessionId: session.id)) ?? []
        refreshSummaryState()
    }

    func refreshSummaryState() {
        if case .generating = summaryState { return }
        if let json = session.summaryJSON,
           let summary = try? JSONDecoder().decode(MeetingSummary.self, from: Data(json.utf8)) {
            summaryState = .available(summary)
            return
        }
        switch availability.status {
        case .tierA: summaryState = .none
        case .tierB(let reason): summaryState = .requiresAppleIntelligence(reason)
        }
    }

    func generateSummary() async {
        let snapshots = segments.map {
            SegmentText(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
        }
        let previous = summaryState
        summaryState = .generating(.planning)
        do {
            let summary = try await summarizer.summarize(segments: snapshots) { [weak self] progress in
                Task { @MainActor in
                    if case .generating = self?.summaryState { self?.summaryState = .generating(progress) }
                }
            }
            let json = String(data: try JSONEncoder().encode(summary), encoding: .utf8)
            try? await repository.update(
                SessionSnapshot(id: session.id, title: session.title, createdAt: session.createdAt,
                                updatedAt: Date(), duration: session.duration, summaryJSON: json,
                                origin: session.origin, tags: session.tags))
            session.summaryJSON = json
            summaryState = .available(summary)
        } catch is CancellationError {
            summaryState = previous
        } catch SummarizerError.notEnoughContent {
            summaryState = .failed("Not enough transcript to summarize.")
        } catch SummarizerError.tooLong {
            summaryState = .failed("This session is too long to summarize.")
        } catch {
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
