import Testing
import Foundation
@testable import EchoMind

@Suite struct SessionSearchTests {
    private func seed() async throws -> any SessionRepository {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let a = UUID(), b = UUID()
        try await repo.create(SessionSnapshot(id: a, title: "Budget Review",
                                              createdAt: Date(timeIntervalSince1970: 2000)))
        try await repo.appendSegment(SegmentSnapshot(sessionId: a, text: "We discussed the quarterly refund policy.",
                                                     startTime: 0, endTime: 3), toSession: a)
        try await repo.create(SessionSnapshot(id: b, title: "Design Sync",
                                              createdAt: Date(timeIntervalSince1970: 1000)))
        try await repo.appendSegment(SegmentSnapshot(sessionId: b, text: "Talked about the new onboarding flow.",
                                                     startTime: 0, endTime: 3), toSession: b)
        return repo
    }

    @Test func matchesByTitle() async throws {
        let repo = try await seed()
        let results = try await repo.search(matching: "design")
        #expect(results.map(\.title) == ["Design Sync"])
    }

    @Test func matchesBySegmentText() async throws {
        let repo = try await seed()
        let results = try await repo.search(matching: "refund")
        #expect(results.map(\.title) == ["Budget Review"])
    }

    @Test func searchIsCaseAndDiacriticInsensitive() async throws {
        let repo = try await seed()
        #expect(try await repo.search(matching: "REFUND").count == 1)
    }

    @Test func emptyQueryReturnsAllSortedByDateDescending() async throws {
        let repo = try await seed()
        let results = try await repo.search(matching: "  ")
        #expect(results.map(\.title) == ["Budget Review", "Design Sync"])
    }

    @Test func recentSessionsRespectsLimit() async throws {
        let repo = try await seed()
        #expect(try await repo.recentSessions(limit: 1).count == 1)
        #expect(try await repo.recentSessions(limit: nil).count == 2)
    }

    @Test func previewTextCollapsesWhitespaceAndTruncates() async throws {
        let repo = try await seed()
        let all = try await repo.recentSessions(limit: nil)
        let preview = try await repo.previewText(sessionID: all[0].id, maxCharacters: 10)
        #expect(preview.count <= 10)
    }

    @Test func renameUpdatesTitle() async throws {
        let repo = try await seed()
        let all = try await repo.recentSessions(limit: nil)
        try await repo.rename(sessionID: all[0].id, to: "Renamed")
        #expect(try await repo.fetchSession(id: all[0].id)?.title == "Renamed")
    }
}
