import Foundation
import PDFKit

/// Per-page PDF text extraction with scanned/locked detection (§4.3 step 4/6).
nonisolated struct PDFTextExtractor {
    func extract(data: Data) throws -> ExtractedText {
        guard let document = PDFDocument(data: data) else {
            throw ImportError.unreadable(underlying: "Could not open PDF")
        }
        if document.isLocked { throw ImportError.passwordProtectedPDF }

        let pageCount = document.pageCount
        var pages: [ExtractedPage] = []
        for index in 0..<pageCount {
            let cleaned = autoreleasepool { () -> String in
                TextCleaner.clean(document.page(at: index)?.string ?? "")
            }
            pages.append(ExtractedPage(pageNumber: index + 1, text: cleaned))
        }

        // Scanned detection on cleaned text (mixed PDFs pass; only text pages count).
        let totalCharacters = pages.reduce(0) { $0 + $1.text.count }
        let threshold = max(50, 10 * pageCount)
        if pageCount >= 1 && totalCharacters < threshold {
            throw ImportError.scannedPDF
        }

        return ExtractedText(pages: pages, pageCount: pageCount)
    }
}
