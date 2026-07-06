import Foundation
import SwiftData

/// Builds the app's `ModelContainer`. `live()` is on-disk, CloudKit-disabled,
/// and applies `.completeUnlessOpen` file protection to the store and its WAL
/// sidecars (§2.3). `inMemory()` is for tests and previews.
nonisolated enum ModelContainerFactory {
    static func live() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let url = try storeURL()
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        applyFileProtection(to: url)
        return container
    }

    static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - Store location

    private static func storeURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("EchoMind", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("EchoMind.store")
    }

    /// Apply `.completeUnlessOpen` to the store and its `-wal`/`-shm` sidecars —
    /// WAL files are where locked-phone writes land, so missing them is the
    /// classic file-protection bug. Attributes are inert on the simulator.
    private static func applyFileProtection(to storeURL: URL) {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUnlessOpen]
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            guard fileManager.fileExists(atPath: path) else { continue }
            try? fileManager.setAttributes(attributes, ofItemAtPath: path)
            #if DEBUG
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let protection = attrs[.protectionKey] {
                print("[Storage] protection \((path as NSString).lastPathComponent): \(protection)")
            }
            #endif
        }
    }
}
