import SwiftUI

#if DEBUG
/// End-to-end proof that container + actor-isolated repositories + cascade rules
/// work in the running app (§2.9). Insert a dummy session with 3 segments, show
/// counts, and cascade-delete — segment count should return to baseline.
struct DebugStorageSection: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var status: String = "—"

    private static let dummyTitle = "DEBUG Dummy Session"

    var body: some View {
        Section("Debug — Storage") {
            Button("Insert dummy session") { Task { await insertDummy() } }
            Button("Fetch counts") { Task { await fetchCounts() } }
            Button("Delete dummy sessions", role: .destructive) { Task { await deleteDummies() } }
            Text(status)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func insertDummy() async {
        do {
            let sessionId = UUID()
            try await dependencies.sessionRepository.create(
                SessionSnapshot(id: sessionId, title: Self.dummyTitle, duration: 42))
            for index in 0..<3 {
                try await dependencies.sessionRepository.appendSegment(
                    SegmentSnapshot(sessionId: sessionId, text: "Segment \(index)",
                                    startTime: Double(index) * 5, endTime: Double(index) * 5 + 4),
                    toSession: sessionId)
            }
            status = "Inserted session + 3 segments"
        } catch {
            status = "Insert failed: \(error)"
        }
    }

    private func fetchCounts() async {
        do {
            let sessions = try await dependencies.sessionRepository.fetchAll()
            var segmentTotal = 0
            for session in sessions {
                segmentTotal += try await dependencies.sessionRepository.fetchSegments(sessionId: session.id).count
            }
            let chunks = try await dependencies.chunkRepository.fetchAll().count
            status = "sessions: \(sessions.count) · segments: \(segmentTotal) · chunks: \(chunks)"
        } catch {
            status = "Fetch failed: \(error)"
        }
    }

    private func deleteDummies() async {
        do {
            let dummies = try await dependencies.sessionRepository.fetchAll()
                .filter { $0.title == Self.dummyTitle }
            for dummy in dummies {
                try await dependencies.sessionRepository.delete(id: dummy.id)
            }
            status = "Deleted \(dummies.count) dummy session(s)"
        } catch {
            status = "Delete failed: \(error)"
        }
    }
}
#endif
