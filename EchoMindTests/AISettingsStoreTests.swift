import Testing
import Foundation
@testable import EchoMind

@Suite @MainActor struct AISettingsStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "echomind.tests.ai.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func defaultsAreAutoAndNoLocalModel() {
        let store = AISettingsStore(defaults: freshDefaults())
        #expect(store.preference == .auto)
        #expect(store.selectedModelID == LocalModelCatalog.default.id)
        #expect(store.localModelID == nil)          // nothing downloaded yet
    }

    @Test func preferencePersistsAcrossInstances() {
        let d = freshDefaults()
        let a = AISettingsStore(defaults: d)
        a.preference = .preferLocal
        let b = AISettingsStore(defaults: d)
        #expect(b.preference == .preferLocal)
    }

    @Test func localModelIDResolvesOnlyWhenSelectedIsDownloaded() {
        let store = AISettingsStore(defaults: freshDefaults())
        let id = store.selectedModelID
        #expect(store.localModelID == nil)
        store.markDownloaded(id)
        #expect(store.localModelID == id)
        store.markRemoved(id)
        #expect(store.localModelID == nil)
    }

    @Test func downloadedSetPersists() {
        let d = freshDefaults()
        let a = AISettingsStore(defaults: d)
        a.markDownloaded("qwen2.5-3b-instruct-4bit")
        let b = AISettingsStore(defaults: d)
        #expect(b.isDownloaded("qwen2.5-3b-instruct-4bit"))
    }
}
