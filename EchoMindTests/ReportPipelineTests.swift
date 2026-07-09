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
