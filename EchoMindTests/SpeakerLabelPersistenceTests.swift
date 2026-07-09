import Testing
import Foundation
@testable import EchoMind

@Suite struct SpeakerLabelPersistenceTests {
    @Test func setSpeakerLabelsPersistsPerSegment() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let sessionId = UUID()
        let seg1 = UUID(), seg2 = UUID()
        try await repo.create(SessionSnapshot(id: sessionId, title: "S"))
        try await repo.appendSegment(
            SegmentSnapshot(id: seg1, sessionId: sessionId, text: "hi", startTime: 0, endTime: 1),
            toSession: sessionId)
        try await repo.appendSegment(
            SegmentSnapshot(id: seg2, sessionId: sessionId, text: "there", startTime: 1, endTime: 2),
            toSession: sessionId)

        try await repo.setSpeakerLabels([seg1: "Speaker 1", seg2: "Speaker 2"], sessionId: sessionId)

        let segments = try await repo.fetchSegments(sessionId: sessionId)
        #expect(segments.first { $0.id == seg1 }?.speakerLabel == "Speaker 1")
        #expect(segments.first { $0.id == seg2 }?.speakerLabel == "Speaker 2")
    }

    @Test func setSpeakerLabelsIgnoresUnknownSegments() async throws {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataSessionRepository(modelContainer: container)
        let sessionId = UUID()
        let seg = UUID()
        try await repo.create(SessionSnapshot(id: sessionId, title: "S"))
        try await repo.appendSegment(
            SegmentSnapshot(id: seg, sessionId: sessionId, text: "x", startTime: 0, endTime: 1),
            toSession: sessionId)

        // A label for a non-existent segment id is simply ignored.
        try await repo.setSpeakerLabels([UUID(): "Speaker 9"], sessionId: sessionId)
        let segments = try await repo.fetchSegments(sessionId: sessionId)
        #expect(segments.first?.speakerLabel == nil)
    }
}
