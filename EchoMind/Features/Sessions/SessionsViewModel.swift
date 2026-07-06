import Foundation

@MainActor
@Observable
final class SessionsViewModel {
    private(set) var sessions: [SessionSnapshot] = []
    private let repository: any SessionRepository

    init(repository: any SessionRepository) {
        self.repository = repository
    }

    func load() async {
        sessions = (try? await repository.recentSessions(limit: nil)) ?? []
    }

    func applySearch(_ query: String) async {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await load()
        } else {
            sessions = (try? await repository.search(matching: query)) ?? []
        }
    }

    func delete(ids: [UUID]) async {
        for id in ids { try? await repository.delete(id: id) }
        await load()
    }
}
