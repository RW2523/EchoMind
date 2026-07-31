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
    /// True when a downloaded local model can generate (dual-mode AI).
    private let localModelReady: () -> Bool
    /// True when this device should be nudged to download a model.
    private let suggestDownload: () -> Bool

    init(repository: any SessionRepository,
         memory: (any MemoryStore)? = nil,
         availability: (any AvailabilityProviding)? = nil,
         localModelReady: @escaping () -> Bool = { false },
         suggestDownload: @escaping () -> Bool = { false }) {
        self.repository = repository
        self.memory = memory
        self.availability = availability
        self.localModelReady = localModelReady
        self.suggestDownload = suggestDownload
    }

    /// Live AI status for the header pill. Dual-mode: Apple Intelligence when the
    /// device has it, the downloaded on-device model otherwise, and a download
    /// nudge when neither generator is available yet.
    var aiStatus: (title: String, ok: Bool) {
        switch availability?.status {
        case .tierA: return ("Apple Intelligence ready", true)
        case .tierB, .none:
            if localModelReady() { return ("On-device model active", true) }
            if suggestDownload() { return ("AI off — download a model", false) }
            return ("On-device · ready", false)
        }
    }

    /// Show a tappable "enable AI" call-to-action row on the status card.
    var showModelDownloadCTA: Bool { availability?.status != .tierA && suggestDownload() }

    func load() async {
        availability?.refresh()
        let all = (try? await repository.recentSessions(limit: nil)) ?? []
        recent = Array(all.prefix(3))
        sessionCount = all.count
        categoryCount = Set(all.compactMap { $0.tags.first }.filter { !$0.isEmpty }).count
        memoryCount = (try? await memory?.count()) ?? 0
    }
}
