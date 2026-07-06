import Foundation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var recent: [SessionSnapshot] = []
    private let repository: any SessionRepository

    init(repository: any SessionRepository) {
        self.repository = repository
    }

    func load() async {
        recent = (try? await repository.recentSessions(limit: 3)) ?? []
    }
}
