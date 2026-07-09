import Foundation

/// Recovers reports that never finished (R1 hardening). The only auto-trigger for
/// report generation is the post-stop Task in `LiveTranscriptViewModel`; if the app
/// is killed mid-generation, or the summarizer errored, or Apple Intelligence was
/// off when the meeting was recorded, that session's report stays stranded forever
/// (nothing re-drives it besides opening the detail view). Running once at launch,
/// this sweeps those sessions and re-drives `generateReport`.
nonisolated protocol ReportReconciling: Sendable {
    func reconcile() async
}

nonisolated struct ReportReconciler: ReportReconciling {
    let sessions: any SessionRepository
    let reportGenerator: any ReportGenerating
    let availability: @Sendable () async -> AvailabilityStatus

    func reconcile() async {
        guard let all = try? await sessions.fetchAll() else { return }
        let aiAvailable: Bool
        if case .tierB = await availability() { aiAvailable = false } else { aiAvailable = true }

        let stranded = all.filter { Self.needsRetry($0, aiAvailable: aiAvailable) }
        // Sequential on purpose: each report runs a map-reduce summarize + grouping +
        // distill, so firing them all at once would spike memory/thermals on launch.
        for snapshot in stranded {
            await reportGenerator.generateReport(sessionId: snapshot.id)
        }
    }

    /// A session needs a retry when its report was interrupted (`pending` with no
    /// summary yet) or errored (`failed`), or when it was skipped for lack of AI
    /// (`unavailable`) that has since become available. `ready`/`none` are left alone.
    static func needsRetry(_ s: SessionSnapshot, aiAvailable: Bool) -> Bool {
        switch s.reportState {
        case .pending:      return s.summaryJSON == nil
        case .failed:       return true
        case .unavailable:  return aiAvailable
        case .ready, .none: return false
        }
    }
}
