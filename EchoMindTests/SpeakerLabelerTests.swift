import Testing
import Foundation
@testable import EchoMind

@Suite struct SpeakerLabelerTests {
    private func span(_ id: UUID, _ start: TimeInterval, _ end: TimeInterval) -> SpeakerLabeler.Span {
        SpeakerLabeler.Span(id: id, start: start, end: end)
    }

    @Test func overlapComputesIntersection() {
        #expect(SpeakerLabeler.overlap(0, 10, 5, 15) == 5)
        #expect(SpeakerLabeler.overlap(0, 5, 5, 10) == 0)   // touching, no overlap
        #expect(SpeakerLabeler.overlap(0, 10, 20, 30) == 0) // disjoint
        #expect(SpeakerLabeler.overlap(2, 8, 0, 10) == 6)   // fully contained
    }

    @Test func assignsSegmentToMostOverlappingSpeaker() {
        let a = UUID(), b = UUID()
        let transcript = [span(a, 0, 5), span(b, 6, 10)]
        let diarization = [
            SpeakerSegment(speaker: "Speaker 1", start: 0, end: 5.5),
            SpeakerSegment(speaker: "Speaker 2", start: 5.5, end: 10),
        ]
        let labels = SpeakerLabeler.assign(transcript: transcript, diarization: diarization)
        #expect(labels[a] == "Speaker 1")
        #expect(labels[b] == "Speaker 2")
    }

    @Test func choosesSpeakerWithGreaterOverlapWhenSegmentSpansTwo() {
        let a = UUID()
        // Segment 0–10 overlaps Speaker 1 for 3s (0–3) and Speaker 2 for 7s (3–10).
        let diarization = [
            SpeakerSegment(speaker: "Speaker 1", start: 0, end: 3),
            SpeakerSegment(speaker: "Speaker 2", start: 3, end: 10),
        ]
        let labels = SpeakerLabeler.assign(transcript: [span(a, 0, 10)], diarization: diarization)
        #expect(labels[a] == "Speaker 2")
    }

    @Test func leavesUnlabelledWhenNoOverlap() {
        let a = UUID()
        let diarization = [SpeakerSegment(speaker: "Speaker 1", start: 100, end: 110)]
        let labels = SpeakerLabeler.assign(transcript: [span(a, 0, 10)], diarization: diarization)
        #expect(labels[a] == nil)
    }

    @Test func emptyDiarizationLabelsNothing() {
        let a = UUID()
        #expect(SpeakerLabeler.assign(transcript: [span(a, 0, 5)], diarization: []).isEmpty)
    }

    @Test func tieBreaksDeterministicallyToSmallerLabel() {
        let a = UUID()
        // Equal overlap (2s each) → smaller label wins, regardless of dict order.
        let diarization = [
            SpeakerSegment(speaker: "Speaker 2", start: 0, end: 2),
            SpeakerSegment(speaker: "Speaker 1", start: 2, end: 4),
        ]
        let labels = SpeakerLabeler.assign(transcript: [span(a, 0, 4)], diarization: diarization)
        #expect(labels[a] == "Speaker 1")
    }
}

@Suite struct DiarizationResultTests {
    @Test func speakerCountCountsDistinct() {
        let r = DiarizationResult(segments: [
            .init(speaker: "Speaker 1", start: 0, end: 1),
            .init(speaker: "Speaker 2", start: 1, end: 2),
            .init(speaker: "Speaker 1", start: 2, end: 3),
        ])
        #expect(r.speakerCount == 2)
    }

    @Test func unavailableServiceThrows() async {
        let service = UnavailableDiarizationService()
        #expect(service.isAvailable == false)
        await #expect(throws: DiarizationError.self) {
            _ = try await service.diarize(audioURL: URL(fileURLWithPath: "/tmp/none.m4a"))
        }
    }
}
