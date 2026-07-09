import Foundation

/// On-disk home for retained session audio (V2 P17). One `.m4a` per session, named
/// by session id, under Application Support/Audio. Keeping the path derivable from
/// the id means no schema column — "does this session have audio?" is a file check.
/// All file ops are best-effort and never throw into the recording hot path.
nonisolated struct AudioStore: Sendable {
    let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
            self.baseDirectory = support.appendingPathComponent("Audio", isDirectory: true)
        }
    }

    func url(for sessionId: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(sessionId.uuidString).m4a")
    }

    /// Creates the audio directory if needed; returns the file URL to write to.
    /// The directory is set to `.completeUnlessOpen` so recordings are encrypted at
    /// rest but stay writable during background recording while the phone is locked.
    func prepareURL(for sessionId: UUID) throws -> URL {
        try FileManager.default.createDirectory(
            at: baseDirectory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: baseDirectory.path)
        return url(for: sessionId)
    }

    func exists(_ sessionId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: sessionId).path)
    }

    func fileSize(_ sessionId: UUID) -> Int64 {
        size(of: url(for: sessionId))
    }

    func remove(_ sessionId: UUID) {
        try? FileManager.default.removeItem(at: url(for: sessionId))
    }

    /// Total bytes of all retained audio (for Settings ▸ Storage).
    func totalBytes() -> Int64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.filter { $0.pathExtension == "m4a" }.reduce(0) { $0 + size(of: $1) }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }

    private func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
