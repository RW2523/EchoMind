import Foundation

@MainActor
@Observable
final class SessionDetailViewModel {
    private(set) var session: SessionSnapshot
    private(set) var segments: [SegmentSnapshot] = []
    var draftTitle: String

    private let repository: any SessionRepository

    init(session: SessionSnapshot, repository: any SessionRepository) {
        self.session = session
        self.draftTitle = session.title
        self.repository = repository
    }

    func load() async {
        segments = (try? await repository.fetchSegments(sessionId: session.id)) ?? []
    }

    func commitRename() async {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { draftTitle = session.title; return }
        try? await repository.rename(sessionID: session.id, to: trimmed)
        session.title = trimmed
    }

    func delete() async {
        try? await repository.delete(id: session.id)
    }

    var markdownExport: SessionExport {
        SessionExport(fileName: SessionExporter.sanitizedFileName(session.title, ext: "md"),
                      contents: SessionExporter.markdown(session: session, segments: segments))
    }

    var textExport: SessionExport {
        SessionExport(fileName: SessionExporter.sanitizedFileName(session.title, ext: "txt"),
                      contents: SessionExporter.plainText(session: session, segments: segments))
    }
}
