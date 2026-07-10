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
            Button("Insert + index sample document") { Task { await insertSampleDocument() } }
            Button("Insert 9,000-word fixture") { Task { await insertFixture() } }
            Button("Run retrieval eval") { Task { await runEval() } }
            Button("Run retrieval benchmark") { Task { await runBenchmark() } }
            Button("Fetch counts") { Task { await fetchCounts() } }
            Button("Delete dummy sessions", role: .destructive) { Task { await deleteDummies() } }
            Text(status)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Recall@k + MRR over the fixed handbook and (if any recordings exist) a
    /// label-free pass over the real knowledge index. Copy the text to compare
    /// embedders across runs.
    private func runBenchmark() async {
        status = "Running benchmark…"
        let embedder = dependencies.embeddingService
        var report = "Embedder: \(dependencies.embedderIdentity)\n"
        if let handbook = await RetrievalBenchmarkRunner.handbook(embedder: embedder) {
            report += "\n" + handbook.formatted() + "\n"
        }
        if let live = await RetrievalBenchmarkRunner.liveSelfRetrieval(
            sessions: dependencies.sessionRepository,
            chunks: dependencies.chunkRepository,
            embedder: embedder) {
            report += "\n" + live.formatted()
        } else {
            report += "\n(live self-retrieval skipped — no recorded sessions with reports yet)"
        }
        status = report
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

    private func runEval() async {
        let eval = RetrievalEval(embedder: dependencies.embeddingService, search: dependencies.vectorSearch)
        let suite = RetrievalEval.handbookSuite()
        do {
            let result = try await eval.score(chunks: suite.chunks, cases: suite.cases, k: 3)
            status = "Retrieval eval: \(result.hits)/\(result.total) (\(Int(result.score * 100))%)"
                + (result.misses.isEmpty ? "" : " · missed: \(result.misses.joined(separator: "; "))")
        } catch {
            status = "Eval failed: \(error)"
        }
    }

    private func insertSampleDocument() async {
        do {
            let id = UUID()
            try await dependencies.documentRepository.create(
                DocumentSnapshot(id: id, title: DebugFixtures.sampleDocumentTitle, fileName: "handbook.md",
                                 fileType: .md, textContent: DebugFixtures.sampleDocumentText,
                                 pageBreaks: [], status: .imported))
            status = "Inserted document — indexing…"
            try await dependencies.indexer.indexDocument(id: id)
            status = "Sample document indexed — try Ask (e.g. \"what is the refund policy?\")"
        } catch {
            status = "Sample doc: created, but indexing failed (\(error)). Ask needs embeddings."
        }
    }

    private func insertFixture() async {
        do {
            let id = UUID()
            try await dependencies.sessionRepository.create(
                SessionSnapshot(id: id, title: "Fixture Meeting", origin: .live))
            let segments = DebugFixtures.meetingSegments()
            for segment in segments {
                try await dependencies.sessionRepository.appendSegment(
                    SegmentSnapshot(sessionId: id, text: segment.text,
                                    startTime: segment.startTime, endTime: segment.endTime),
                    toSession: id)
            }
            status = "Inserted fixture with \(segments.count) segments"
        } catch {
            status = "Fixture failed: \(error)"
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
