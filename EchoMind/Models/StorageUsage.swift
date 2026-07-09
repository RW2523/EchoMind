import Foundation

nonisolated struct StorageUsage: Sendable, Equatable {
    let sessionsBytes: Int64    // segments + stored summaries
    let documentsBytes: Int64   // extracted text
    let indexBytes: Int64       // chunk text + packed embeddings
    let audioBytes: Int64       // retained session audio (P17)

    var totalBytes: Int64 { sessionsBytes + documentsBytes + indexBytes + audioBytes }

    init(sessionsBytes: Int64, documentsBytes: Int64, indexBytes: Int64, audioBytes: Int64 = 0) {
        self.sessionsBytes = sessionsBytes
        self.documentsBytes = documentsBytes
        self.indexBytes = indexBytes
        self.audioBytes = audioBytes
    }

    static let zero = StorageUsage(sessionsBytes: 0, documentsBytes: 0, indexBytes: 0, audioBytes: 0)
}
