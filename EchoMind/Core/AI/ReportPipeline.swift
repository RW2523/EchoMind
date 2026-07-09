import Foundation

/// Generates a session's report in the background (R1). Kicked off automatically
/// when recording stops, and retried when a session detail opens in a `.pending`
/// (interrupted) or `.failed` state. Persists `summaryJSON` + `reportState` through
/// the repository's report-only setters so it never clobbers title/tags/etc.
nonisolated protocol ReportGenerating: Sendable {
    func generateReport(sessionId: UUID) async
}

nonisolated struct ReportPipeline: ReportGenerating {
    let sessions: any SessionRepository
    let summarizer: any SummarizerService
    let availability: @Sendable () async -> AvailabilityStatus

    func generateReport(sessionId: UUID) async {
        // Tier B: no generator — record it and leave the manual path for later.
        if case .tierB = await availability() {
            try? await sessions.setReportState(.unavailable, sessionId: sessionId)
            return
        }

        try? await sessions.setReportState(.pending, sessionId: sessionId)

        let segments = (try? await sessions.fetchSegments(sessionId: sessionId)) ?? []
        guard !segments.isEmpty else {
            try? await sessions.setReportState(.failed, sessionId: sessionId)
            return
        }

        let texts = segments.map {
            SegmentText(text: $0.text, startTime: $0.startTime, endTime: $0.endTime)
        }
        do {
            let summary = try await summarizer.summarize(segments: texts) { _ in }
            let json = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
            try await sessions.setReport(summaryJSON: json, sessionId: sessionId)
        } catch {
            try? await sessions.setReportState(.failed, sessionId: sessionId)
        }
    }
}
