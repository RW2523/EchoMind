import Foundation

nonisolated struct StorageUsage: Sendable, Equatable {
    let sessionsBytes: Int64    // segments + stored summaries
    let documentsBytes: Int64   // extracted text
    let indexBytes: Int64       // chunk text + packed embeddings

    var totalBytes: Int64 { sessionsBytes + documentsBytes + indexBytes }

    static let zero = StorageUsage(sessionsBytes: 0, documentsBytes: 0, indexBytes: 0)
}
