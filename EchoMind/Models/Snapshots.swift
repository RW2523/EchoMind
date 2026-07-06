import Foundation

/// Sendable value types exchanged across the storage boundary. `@Model` classes
/// are not Sendable and never leave `Core/Storage`; repositories accept and
/// return these snapshots instead (§2.4). All fields are value types so these
/// cross actor boundaries freely under Swift 6 strict concurrency.

nonisolated struct SessionSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var summaryJSON: String?
    var origin: SessionOrigin
    var tags: [String]

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), updatedAt: Date = Date(),
         duration: TimeInterval = 0, summaryJSON: String? = nil, origin: SessionOrigin = .live,
         tags: [String] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.summaryJSON = summaryJSON
        self.origin = origin
        self.tags = tags
    }
}

nonisolated struct SegmentSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var sessionId: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var speakerLabel: String?
    var createdAt: Date

    init(id: UUID = UUID(), sessionId: UUID, text: String, startTime: TimeInterval,
         endTime: TimeInterval, speakerLabel: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speakerLabel = speakerLabel
        self.createdAt = createdAt
    }
}

nonisolated struct DocumentSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var fileName: String
    var fileType: DocumentFileType
    var textContent: String
    var pageCount: Int?
    var pageBreaks: [Int]
    var status: DocumentStatus
    var createdAt: Date

    init(id: UUID = UUID(), title: String, fileName: String, fileType: DocumentFileType,
         textContent: String, pageCount: Int? = nil, pageBreaks: [Int] = [],
         status: DocumentStatus = .imported, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.fileType = fileType
        self.textContent = textContent
        self.pageCount = pageCount
        self.pageBreaks = pageBreaks
        self.status = status
        self.createdAt = createdAt
    }
}

nonisolated struct ChunkSnapshot: Sendable, Hashable, Identifiable {
    var id: UUID
    var sourceId: UUID
    var sourceType: SourceType
    var text: String
    var embedding: Data
    var chunkIndex: Int
    var pageNumber: Int?
    var timestamp: TimeInterval?
    var createdAt: Date

    init(id: UUID = UUID(), sourceId: UUID, sourceType: SourceType, text: String,
         embedding: Data = Data(), chunkIndex: Int, pageNumber: Int? = nil,
         timestamp: TimeInterval? = nil, createdAt: Date = Date()) {
        self.id = id
        self.sourceId = sourceId
        self.sourceType = sourceType
        self.text = text
        self.embedding = embedding
        self.chunkIndex = chunkIndex
        self.pageNumber = pageNumber
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}
