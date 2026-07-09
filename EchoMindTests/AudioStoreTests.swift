import Testing
import Foundation
@testable import EchoMind

@Suite struct AudioStoreTests {
    private func tempStore() -> AudioStore {
        AudioStore(baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("echomind-audiostore-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func urlIsDerivedFromSessionId() {
        let store = tempStore()
        let id = UUID()
        #expect(store.url(for: id).lastPathComponent == "\(id.uuidString).m4a")
    }

    @Test func existsSizeAndRemove() throws {
        let store = tempStore()
        let id = UUID()
        #expect(store.exists(id) == false)
        try Data(repeating: 7, count: 128).write(to: store.prepareURL(for: id))
        #expect(store.exists(id))
        #expect(store.fileSize(id) == 128)
        store.remove(id)
        #expect(store.exists(id) == false)
    }

    @Test func totalBytesSumsOnlyM4A() throws {
        let store = tempStore()
        try Data(repeating: 1, count: 100).write(to: store.prepareURL(for: UUID()))
        try Data(repeating: 1, count: 50).write(to: store.prepareURL(for: UUID()))
        // A non-audio file in the same dir must be ignored.
        try Data(repeating: 1, count: 999).write(
            to: store.baseDirectory.appendingPathComponent("stray.txt"))
        #expect(store.totalBytes() == 150)
    }

    @Test func removeAllClearsEverything() throws {
        let store = tempStore()
        let id = UUID()
        try Data(repeating: 1, count: 10).write(to: store.prepareURL(for: id))
        store.removeAll()
        #expect(store.exists(id) == false)
        #expect(store.totalBytes() == 0)
    }
}

@Suite struct StorageUsageAudioTests {
    @Test func totalIncludesAudioBytes() {
        let usage = StorageUsage(sessionsBytes: 10, documentsBytes: 20, indexBytes: 30, audioBytes: 40)
        #expect(usage.totalBytes == 100)
    }

    @Test func audioDefaultsToZero() {
        let usage = StorageUsage(sessionsBytes: 1, documentsBytes: 2, indexBytes: 3)
        #expect(usage.audioBytes == 0)
        #expect(usage.totalBytes == 6)
    }
}
