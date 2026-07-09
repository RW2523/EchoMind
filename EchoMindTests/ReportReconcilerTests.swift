import XCTest
@testable import EchoMind

/// Bug 3: reports stranded by an interrupted / failed / AI-unavailable launch must
/// be re-driven at next launch. These pin the pure retry policy.
final class ReportReconcilerTests: XCTestCase {
    private func session(_ state: ReportState, summary: String? = nil) -> SessionSnapshot {
        SessionSnapshot(title: "t", summaryJSON: summary, reportState: state)
    }

    func testPendingWithoutSummaryRetries() {
        XCTAssertTrue(ReportReconciler.needsRetry(session(.pending), aiAvailable: true))
    }

    func testPendingWithSummaryDoesNotRetry() {
        // A partially-persisted report that already has a summary is effectively done.
        XCTAssertFalse(ReportReconciler.needsRetry(session(.pending, summary: "{}"), aiAvailable: true))
    }

    func testFailedAlwaysRetries() {
        XCTAssertTrue(ReportReconciler.needsRetry(session(.failed), aiAvailable: true))
    }

    func testUnavailableRetriesOnlyWhenAINowAvailable() {
        XCTAssertTrue(ReportReconciler.needsRetry(session(.unavailable), aiAvailable: true))
        XCTAssertFalse(ReportReconciler.needsRetry(session(.unavailable), aiAvailable: false))
    }

    func testReadyAndNoneAreLeftAlone() {
        XCTAssertFalse(ReportReconciler.needsRetry(session(.ready, summary: "{}"), aiAvailable: true))
        XCTAssertFalse(ReportReconciler.needsRetry(session(.none), aiAvailable: true))
    }

    func testFailedNotRetriedIsUnaffectedByAIFlag() {
        // Failed is retriable regardless — a transient summarizer error, not an AI gap.
        XCTAssertTrue(ReportReconciler.needsRetry(session(.failed), aiAvailable: false))
    }
}
