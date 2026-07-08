import Foundation

/// Real byte counts summed from stored text + embeddings (§7.1), off the main actor.
nonisolated protocol StorageUsageService: Sendable {
    func usage() async throws -> StorageUsage
}

/// One Markdown file per session + a documents manifest, in a temp dir (§7.1).
nonisolated protocol DataExportService: Sendable {
    func exportAll() async throws -> [URL]
}

/// Wipes sessions/segments/documents/chunks/chat; keeps onboarding+consent (§7.1).
nonisolated protocol DataWipeService: Sendable {
    func deleteAllData() async throws
}

nonisolated struct DefaultStorageUsageService: StorageUsageService {
    let sessions: any SessionRepository
    let documents: any DocumentRepository
    let chunks: any ChunkRepository
    var audioStore = AudioStore()

    func usage() async throws -> StorageUsage {
        var sessionsBytes: Int64 = 0
        for session in try await sessions.fetchAll() {
            sessionsBytes += Int64(session.summaryJSON?.utf8.count ?? 0)
            let segments = try await sessions.fetchSegments(sessionId: session.id)
            sessionsBytes += segments.reduce(Int64(0)) { $0 + Int64($1.text.utf8.count) }
        }
        let documentsBytes = try await documents.fetchAll()
            .reduce(Int64(0)) { $0 + Int64($1.textContent.utf8.count) }
        let indexBytes = try await chunks.fetchAll()
            .reduce(Int64(0)) { $0 + Int64($1.text.utf8.count + $1.embedding.count) }
        return StorageUsage(sessionsBytes: sessionsBytes, documentsBytes: documentsBytes,
                            indexBytes: indexBytes, audioBytes: audioStore.totalBytes())
    }
}

nonisolated struct DefaultDataExportService: DataExportService {
    let sessions: any SessionRepository
    let documents: any DocumentRepository

    func exportAll() async throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EchoMindExportAll-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var urls: [URL] = []
        for session in try await sessions.fetchAll() {
            let segments = try await sessions.fetchSegments(sessionId: session.id)
            var markdown = SessionExporter.markdown(session: session, segments: segments)
            if let json = session.summaryJSON,
               let summary = try? JSONDecoder().decode(MeetingSummary.self, from: Data(json.utf8)) {
                markdown += "\n## Summary\n\n" + Self.summaryMarkdown(summary)
            }
            let url = directory.appendingPathComponent(SessionExporter.sanitizedFileName(session.title, ext: "md"))
            try markdown.data(using: .utf8)?.write(to: url)
            urls.append(url)
        }

        let docs = try await documents.fetchAll()
        if !docs.isEmpty {
            var manifest = "# Imported Documents\n\n"
            for document in docs { manifest += "- \(document.title) (\(document.fileName))\n" }
            let url = directory.appendingPathComponent("documents-list.md")
            try manifest.data(using: .utf8)?.write(to: url)
            urls.append(url)
        }
        return urls
    }

    static func summaryMarkdown(_ summary: MeetingSummary) -> String {
        var lines: [String] = []
        if !summary.overview.isEmpty { lines.append(summary.overview); lines.append("") }
        if !summary.keyDecisions.isEmpty {
            lines.append("**Key Decisions**")
            lines.append(contentsOf: summary.keyDecisions.map { "- \($0)" })
            lines.append("")
        }
        if !summary.actionItems.isEmpty {
            lines.append("**Action Items**")
            lines.append(contentsOf: summary.actionItems.map { "- \($0.text)" + ($0.owner.map { " (\($0))" } ?? "") })
            lines.append("")
        }
        if !summary.risks.isEmpty {
            lines.append("**Risks**")
            lines.append(contentsOf: summary.risks.map { "- \($0)" })
            lines.append("")
        }
        if !summary.openQuestions.isEmpty {
            lines.append("**Open Questions**")
            lines.append(contentsOf: summary.openQuestions.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

nonisolated struct DefaultDataWipeService: DataWipeService {
    let sessions: any SessionRepository
    let documents: any DocumentRepository
    let chunks: any ChunkRepository
    let chat: any ChatRepository
    var audioStore = AudioStore()

    func deleteAllData() async throws {
        for session in try await sessions.fetchAll() { try await sessions.delete(id: session.id) }
        for document in try await documents.fetchAll() { try await documents.delete(id: document.id) }
        try await chunks.deleteAll()
        try await chat.deleteAll()
        audioStore.removeAll()   // P17: retained audio is on disk, not in SwiftData
    }
}
