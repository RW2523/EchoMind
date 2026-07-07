import Foundation

/// Preflight check for low storage (§7.3). Warns below ~200 MB of important-usage
/// capacity so recording/import fail gracefully instead of losing data on a
/// SwiftData save throw.
nonisolated enum StorageGuard {
    static let minimumBytes: Int64 = 200 * 1024 * 1024

    static func hasSufficientSpace() -> Bool {
        let url = FileManager.default.temporaryDirectory
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true   // unknown → don't block
        }
        return available >= minimumBytes
    }
}
