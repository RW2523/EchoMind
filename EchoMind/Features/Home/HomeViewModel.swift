import Foundation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var recent: [SessionSnapshot] = []
    private(set) var sessionCount = 0
    private(set) var categoryCount = 0
    private(set) var memoryCount = 0

    private let repository: any SessionRepository
    private let memory: (any MemoryStore)?
    private let availability: (any AvailabilityProviding)?

    init(repository: any SessionRepository,
         memory: (any MemoryStore)? = nil,
         availability: (any AvailabilityProviding)? = nil) {
        self.repository = repository
        self.memory = memory
        self.availability = availability
    }

    /// Live AI status for the header pill.
    var aiStatus: (title: String, ok: Bool) {
        switch availability?.status {
        case .tierA: return ("Apple Intelligence ready", true)
        case .tierB, .none: return ("On-device · ready", false)
        }
    }

    func load() async {
        availability?.refresh()
        let all = (try? await repository.recentSessions(limit: nil)) ?? []
        recent = Array(all.prefix(3))
        sessionCount = all.count
        categoryCount = Set(all.compactMap { $0.tags.first }.filter { !$0.isEmpty }).count
        memoryCount = (try? await memory?.count()) ?? 0
    }
}
