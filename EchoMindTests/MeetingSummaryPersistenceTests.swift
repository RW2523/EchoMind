import Testing
import Foundation
@testable import EchoMind

@Suite struct MeetingSummaryPersistenceTests {
    @Test func jsonRoundTrip() throws {
        let summary = MeetingSummary(
            overview: "We reviewed Q3 plans.",
            keyDecisions: ["Ship the billing migration in Q3."],
            actionItems: [.init(text: "Run the vendor audit", owner: "Priya"),
                          .init(text: "Draft the DPA", owner: nil)],
            risks: ["Vendor contract expires early."],
            openQuestions: ["Do we need an EU DPA?"])
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(MeetingSummary.self, from: data)
        #expect(decoded == summary)
    }

    @Test func storesAndReloadsViaSessionSummaryJSON() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let id = UUID()
        try await repo.create(SessionSnapshot(id: id, title: "S"))

        let summary = MeetingSummary(overview: "Overview here.")
        let json = String(data: try JSONEncoder().encode(summary), encoding: .utf8)
        try await repo.update(SessionSnapshot(id: id, title: "S", summaryJSON: json))

        let reloaded = try await repo.fetchSession(id: id)
        #expect(reloaded?.summaryJSON == json)
        let decoded = try JSONDecoder().decode(MeetingSummary.self,
                                               from: Data(reloaded!.summaryJSON!.utf8))
        #expect(decoded.overview == "Overview here.")
    }

    @Test func undecodableJSONFailsGracefully() {
        let bad = Data("not valid summary json".utf8)
        #expect((try? JSONDecoder().decode(MeetingSummary.self, from: bad)) == nil)
    }
}
