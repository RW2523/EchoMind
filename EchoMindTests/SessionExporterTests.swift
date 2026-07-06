import Testing
import Foundation
@testable import EchoMind

@Suite struct SessionExporterTests {
    private func fixture() -> (SessionSnapshot, [SegmentSnapshot]) {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000_000)
        let session = SessionSnapshot(id: id, title: "Team Standup", createdAt: created,
                                      updatedAt: created, duration: 2_537, origin: .live)
        let segments = [
            SegmentSnapshot(sessionId: id, text: "First segment text.", startTime: 3, endTime: 5),
            SegmentSnapshot(sessionId: id, text: "Next segment.", startTime: 11, endTime: 14),
        ]
        return (session, segments)
    }

    @Test func timestampIsZeroPaddedHMS() {
        #expect(SessionExporter.timestamp(3) == "00:00:03")
        #expect(SessionExporter.timestamp(671) == "00:11:11")
        #expect(SessionExporter.timestamp(3_661) == "01:01:01")
    }

    @Test func durationDropsLeadingZeroUnits() {
        #expect(SessionExporter.durationText(2_537) == "42m 17s")
        #expect(SessionExporter.durationText(45) == "45s")
        #expect(SessionExporter.durationText(3_725) == "1h 2m 5s")
    }

    @Test func markdownMatchesGolden() {
        let (session, segments) = fixture()
        let expected = """
        # Team Standup

        **Date:** \(SessionExporter.dateText(session.createdAt))
        **Duration:** 42m 17s

        ## Transcript

        **[00:00:03]** First segment text.
        **[00:00:11]** Next segment.

        """
        #expect(SessionExporter.markdown(session: session, segments: segments) == expected)
    }

    @Test func plainTextMatchesGolden() {
        let (session, segments) = fixture()
        let expected = """
        Team Standup
        Date: \(SessionExporter.dateText(session.createdAt))
        Duration: 42m 17s

        [00:00:03] First segment text.
        [00:00:11] Next segment.

        """
        #expect(SessionExporter.plainText(session: session, segments: segments) == expected)
    }

    @Test func segmentsSortedByStartTimeRegardlessOfInputOrder() {
        let id = UUID()
        let session = SessionSnapshot(id: id, title: "T", duration: 10)
        let segments = [
            SegmentSnapshot(sessionId: id, text: "second", startTime: 5, endTime: 6),
            SegmentSnapshot(sessionId: id, text: "first", startTime: 0, endTime: 1),
        ]
        let output = SessionExporter.plainText(session: session, segments: segments)
        let firstIndex = output.range(of: "first")!.lowerBound
        let secondIndex = output.range(of: "second")!.lowerBound
        #expect(firstIndex < secondIndex)
    }

    @Test func sanitizesFileName() {
        #expect(SessionExporter.sanitizedFileName("A/B:C", ext: "md") == "A-B-C.md")
        #expect(SessionExporter.sanitizedFileName("   ", ext: "txt") == "Session.txt")
    }
}
