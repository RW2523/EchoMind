import Testing
import Foundation
@testable import EchoMind

private struct MockSummarizer: SummarizerService {
    let summary: MeetingSummary?
    func summarize(segments: [SegmentText],
                   onProgress: @Sendable @escaping (SummarizerProgress) -> Void) async throws -> MeetingSummary {
        guard let summary else { throw SummarizerError.notEnoughContent }
        return summary
    }
}

private struct MockTitler: SessionTitling {
    let result: String?
    func title(overview: String, decisions: [String]) async -> String? { result }
}

/// Titler that runs a side effect while "generating" — used to interleave a user
/// rename inside the titling window (the TOCTOU race).
private struct HookedTitler: SessionTitling {
    let result: String?
    let whileGenerating: @Sendable () async -> Void
    func title(overview: String, decisions: [String]) async -> String? {
        await whileGenerating()
        return result
    }
}

@Suite struct ReportPipelineTests {
    private func seededRepo() async throws -> (SwiftDataSessionRepository, UUID) {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "Standup"))
        try await repo.appendSegment(
            SegmentSnapshot(sessionId: id, text: "we decided to ship on friday", startTime: 0, endTime: 5),
            toSession: id)
        return (repo, id)
    }

    @Test func generatesReportAndMarksReady() async throws {
        let (repo, id) = try await seededRepo()
        let summary = MeetingSummary(overview: "Shipping", keyDecisions: ["Ship Friday"],
                                     actionItems: [.init(text: "Prep release", owner: "Sam")])
        let pipeline = ReportPipeline(sessions: repo, summarizer: MockSummarizer(summary: summary),
                                      availability: { .tierA })
        await pipeline.generateReport(sessionId: id)

        let fresh = try await repo.fetchSession(id: id)
        #expect(fresh?.reportState == .ready)
        #expect(fresh?.summaryJSON != nil)
        let decoded = try JSONDecoder().decode(MeetingSummary.self, from: Data((fresh?.summaryJSON ?? "").utf8))
        #expect(decoded.keyDecisions == ["Ship Friday"])
    }

    @Test func autoTitlesPlaceholderSession() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try await repo.create(SessionSnapshot(id: id, title: SessionNaming.defaultTitle(created),
                                              createdAt: created))
        try await repo.appendSegment(
            SegmentSnapshot(sessionId: id, text: "we planned the q3 launch", startTime: 0, endTime: 5),
            toSession: id)

        let pipeline = ReportPipeline(
            sessions: repo, summarizer: MockSummarizer(summary: MeetingSummary(overview: "Q3 launch planning")),
            availability: { .tierA }, titler: MockTitler(result: "Q3 Launch Planning"))
        await pipeline.generateReport(sessionId: id)

        #expect(try await repo.fetchSession(id: id)?.title == "Q3 Launch Planning")
    }

    @Test func neverRenamesUserTitledSession() async throws {
        let (repo, id) = try await seededRepo()   // titled "Standup" by the user
        let pipeline = ReportPipeline(
            sessions: repo, summarizer: MockSummarizer(summary: MeetingSummary(overview: "Daily standup")),
            availability: { .tierA }, titler: MockTitler(result: "Engineering Standup"))
        await pipeline.generateReport(sessionId: id)

        #expect(try await repo.fetchSession(id: id)?.title == "Standup")
    }

    @Test func userRenameDuringTitleGenerationWins() async throws {
        // TOCTOU race: the placeholder check passes, then the user renames while the
        // titler's LLM call is in flight. The atomic renameIfPlaceholder must refuse
        // to overwrite the user's title.
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try await repo.create(SessionSnapshot(id: id, title: SessionNaming.defaultTitle(created),
                                              createdAt: created))
        try await repo.appendSegment(
            SegmentSnapshot(sessionId: id, text: "board sync notes", startTime: 0, endTime: 5),
            toSession: id)

        let titler = HookedTitler(result: "AI Generated Title") {
            // User saves a rename mid-generation.
            try? await repo.rename(sessionID: id, to: "Board sync — keep")
        }
        let pipeline = ReportPipeline(
            sessions: repo, summarizer: MockSummarizer(summary: MeetingSummary(overview: "Board sync")),
            availability: { .tierA }, titler: titler)
        await pipeline.generateReport(sessionId: id)

        #expect(try await repo.fetchSession(id: id)?.title == "Board sync — keep")
    }

    @Test func nilTitleKeepsPlaceholder() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let placeholder = SessionNaming.defaultTitle(created)
        try await repo.create(SessionSnapshot(id: id, title: placeholder, createdAt: created))
        try await repo.appendSegment(
            SegmentSnapshot(sessionId: id, text: "hello", startTime: 0, endTime: 1), toSession: id)

        let pipeline = ReportPipeline(
            sessions: repo, summarizer: MockSummarizer(summary: MeetingSummary(overview: "x")),
            availability: { .tierA }, titler: MockTitler(result: nil))
        await pipeline.generateReport(sessionId: id)

        #expect(try await repo.fetchSession(id: id)?.title == placeholder)
    }

    @Test func tierBMarksUnavailableWithoutSummarizing() async throws {
        let (repo, id) = try await seededRepo()
        let pipeline = ReportPipeline(sessions: repo, summarizer: MockSummarizer(summary: MeetingSummary()),
                                      availability: { .tierB(.appleIntelligenceNotEnabled) })
        await pipeline.generateReport(sessionId: id)

        let fresh = try await repo.fetchSession(id: id)
        #expect(fresh?.reportState == .unavailable)
        #expect(fresh?.summaryJSON == nil)
    }

    @Test func emptySessionMarksFailed() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "Empty"))   // no segments
        let pipeline = ReportPipeline(sessions: repo, summarizer: MockSummarizer(summary: MeetingSummary()),
                                      availability: { .tierA })
        await pipeline.generateReport(sessionId: id)
        #expect(try await repo.fetchSession(id: id)?.reportState == .failed)
    }

    @Test func summarizerErrorMarksFailed() async throws {
        let (repo, id) = try await seededRepo()
        let pipeline = ReportPipeline(sessions: repo, summarizer: MockSummarizer(summary: nil),
                                      availability: { .tierA })
        await pipeline.generateReport(sessionId: id)
        #expect(try await repo.fetchSession(id: id)?.reportState == .failed)
    }
}

@Suite struct SessionReportPersistenceTests {
    private func repoWithSession() async throws -> (SwiftDataSessionRepository, UUID) {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "Meeting"))
        return (repo, id)
    }

    @Test func setReportStateDoesNotClobberOtherFields() async throws {
        let (repo, id) = try await repoWithSession()
        try await repo.setReportState(.pending, sessionId: id)
        let fresh = try await repo.fetchSession(id: id)
        #expect(fresh?.title == "Meeting")
        #expect(fresh?.reportState == .pending)
    }

    @Test func setReportPersistsSummaryAndReady() async throws {
        let (repo, id) = try await repoWithSession()
        try await repo.setReport(summaryJSON: "{\"overview\":\"hi\"}", sessionId: id)
        let fresh = try await repo.fetchSession(id: id)
        #expect(fresh?.reportState == .ready)
        #expect(fresh?.summaryJSON == "{\"overview\":\"hi\"}")
    }

    @Test func actionStatesRoundTrip() async throws {
        let (repo, id) = try await repoWithSession()
        try await repo.setActionStates("[true,false,true]", sessionId: id)
        #expect(try await repo.fetchSession(id: id)?.actionStates == [true, false, true])
    }

    @Test func defaultReportStateIsNone() async throws {
        let (repo, id) = try await repoWithSession()
        #expect(try await repo.fetchSession(id: id)?.reportState == ReportState.none)
        #expect(try await repo.fetchSession(id: id)?.actionStates == [])
    }
}
