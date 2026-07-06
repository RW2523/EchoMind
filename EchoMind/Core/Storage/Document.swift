import Foundation
import SwiftData

/// An imported document (.txt/.md/.pdf). `textContent` is externally stored
/// (can approach the 5 MB cap, Phase 6). `pageBreaks` holds the UTF-16 offset
/// into `textContent` at which each page starts (element i = start of page i+1;
/// page 1 starts at 0) so Phase 7 can recover page numbers after the original
/// file is discarded (rag.md §6.2 amendment to spec §8).
@Model
final class Document {
    #Index<Document>([\.createdAt])
    @Attribute(.unique) var id: UUID
    var title: String
    var fileName: String
    var fileTypeRaw: String
    @Attribute(.externalStorage) var textContent: String
    var pageCount: Int?
    var pageBreaks: [Int]
    var statusRaw: String
    var createdAt: Date

    var fileType: DocumentFileType {
        get { DocumentFileType(rawValue: fileTypeRaw) ?? .txt }
        set { fileTypeRaw = newValue.rawValue }
    }

    var status: DocumentStatus {
        get { DocumentStatus(rawValue: statusRaw) ?? .imported }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), title: String, fileName: String, fileType: DocumentFileType,
         textContent: String, pageCount: Int? = nil, pageBreaks: [Int] = [],
         status: DocumentStatus = .imported, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.fileTypeRaw = fileType.rawValue
        self.textContent = textContent
        self.pageCount = pageCount
        self.pageBreaks = pageBreaks
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
    }

    var snapshot: DocumentSnapshot {
        DocumentSnapshot(id: id, title: title, fileName: fileName, fileType: fileType,
                         textContent: textContent, pageCount: pageCount, pageBreaks: pageBreaks,
                         status: status, createdAt: createdAt)
    }
}
