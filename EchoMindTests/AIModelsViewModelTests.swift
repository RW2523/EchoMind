import Testing
import Foundation
@testable import EchoMind

private final class FakeDownloader: ModelDownloadService, @unchecked Sendable {
    let engineLinked: Bool
    var available: Set<String>
    init(engineLinked: Bool = true, available: Set<String> = []) {
        self.engineLinked = engineLinked
        self.available = available
    }
    func isAvailable(_ model: LocalModel) async -> Bool { available.contains(model.id) }
    func delete(_ model: LocalModel) async throws { available.remove(model.id) }
    func download(_ model: LocalModel, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        available.insert(model.id)
        onProgress(1)
    }
}

@Suite @MainActor struct AIModelsViewModelTests {
    private func freshSettings() -> AISettingsStore {
        let suite = "echomind.tests.aimodels.\(UUID().uuidString)"
        return AISettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func firstDownloadRequiresConsent() {
        let vm = AIModelsViewModel(downloader: FakeDownloader(), settings: freshSettings())
        vm.requestDownload(vm.models[0])
        #expect(vm.showConsent)
        #expect(vm.state(for: vm.models[0]) == .notDownloaded)
    }

    @Test func loadReflectsOnDiskAvailability() async {
        let settings = freshSettings()
        let model = LocalModelCatalog.default
        let vm = AIModelsViewModel(downloader: FakeDownloader(available: [model.id]), settings: settings)
        await vm.load()
        #expect(vm.state(for: model) == .ready)
    }

    @Test func selectPersistsToSettings() {
        let settings = freshSettings()
        let vm = AIModelsViewModel(downloader: FakeDownloader(), settings: settings)
        let target = vm.models[1]
        vm.select(target)
        #expect(settings.selectedModelID == target.id)
    }

    @Test func preferenceWritesThrough() {
        let settings = freshSettings()
        let vm = AIModelsViewModel(downloader: FakeDownloader(), settings: settings)
        vm.preference = .localOnly
        #expect(settings.preference == .localOnly)
    }

    @Test func engineLinkedReflectsDownloader() {
        let vm = AIModelsViewModel(downloader: FakeDownloader(engineLinked: false), settings: freshSettings())
        #expect(vm.engineLinked == false)
    }
}
