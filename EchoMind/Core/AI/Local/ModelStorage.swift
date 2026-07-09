import Foundation

/// Tracks which models are downloaded via a marker file in Application Support,
/// independent of the MLX/HF cache layout (which is package-version-specific). The
/// marker is our stable source of truth for "is this model usable"; deleting it
/// makes the router stop choosing the model even if weights linger in the cache.
nonisolated enum ModelStorage {
    static func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func markerURL(for model: LocalModel) throws -> URL {
        try modelsDirectory().appendingPathComponent("\(model.id).downloaded")
    }

    static func isMarked(_ model: LocalModel) -> Bool {
        guard let url = try? markerURL(for: model) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func mark(_ model: LocalModel) throws {
        try Data().write(to: markerURL(for: model))
    }

    static func unmark(_ model: LocalModel) throws {
        let url = try markerURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
