import Foundation

/// Full import pipeline off the main actor; returns the persisted document id
/// (§4.3). Import lives in Core/Storage — its output is a persisted Document.
nonisolated protocol DocumentImportService: Sendable {
    func importDocument(at url: URL) async throws -> UUID
}

nonisolated struct DefaultDocumentImportService: DocumentImportService {
    let documents: any DocumentRepository
    private let extractor = PDFTextExtractor()

    private static let pdfRawLimit = 50 * 1024 * 1024
    private static let textRawLimit = 5 * 1024 * 1024
    private static let extractedLimit = 5 * 1024 * 1024

    func importDocument(at url: URL) async throws -> UUID {
        // Security scope: true for document-picker URLs; false (but still
        // readable) for regular URLs. Only a failed READ is access-denied.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable(underlying: error.localizedDescription)
        }

        let ext = url.pathExtension.lowercased()
        let extracted: ExtractedText
        let fileType: DocumentFileType

        switch ext {
        case "pdf":
            guard data.count <= Self.pdfRawLimit else { throw ImportError.tooLarge(limitMB: 5) }
            extracted = try extractor.extract(data: data)
            fileType = .pdf
        case "txt", "text":
            guard data.count <= Self.textRawLimit else { throw ImportError.tooLarge(limitMB: 5) }
            extracted = plainPage(from: data)
            fileType = .txt
        case "md", "markdown":
            guard data.count <= Self.textRawLimit else { throw ImportError.tooLarge(limitMB: 5) }
            extracted = plainPage(from: data)
            fileType = .md
        default:
            throw ImportError.unsupportedType
        }

        let (text, pageBreaks) = extracted.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyDocument
        }
        guard text.utf8.count <= Self.extractedLimit else { throw ImportError.tooLarge(limitMB: 5) }

        let id = UUID()
        try await documents.create(DocumentSnapshot(
            id: id,
            title: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent,
            fileType: fileType,
            textContent: text,
            pageCount: extracted.pageCount,
            pageBreaks: pageBreaks,
            status: .imported))
        return id
    }

    private func plainPage(from data: Data) -> ExtractedText {
        // UTF-8 -> CP1252 -> Latin-1 (accepts any byte sequence).
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return ExtractedText(pages: [ExtractedPage(pageNumber: nil, text: TextCleaner.clean(raw))],
                             pageCount: nil)
    }
}
