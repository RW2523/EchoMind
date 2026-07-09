import Foundation

/// Lifecycle of a session's auto-generated report (R1). Persisted as a raw string
/// on `Session` (additive column → SwiftData lightweight migration).
nonisolated enum ReportState: String, Sendable, Equatable {
    case none          // not requested yet (imported sessions, pre-R1 rows)
    case pending       // generation kicked off / in flight
    case ready         // summaryJSON populated
    case failed        // generation errored; retriable
    case unavailable   // no generator on this device (Tier B); manual later
}
