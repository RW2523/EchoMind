import Foundation

nonisolated struct ExtractedPage: Equatable, Sendable {
    let pageNumber: Int?
    let text: String
}

/// Extracted document content plus the page-break contract (rag.md §6.2).
nonisolated struct ExtractedText: Equatable, Sendable {
    let pages: [ExtractedPage]
    let pageCount: Int?

    /// Joins pages with "\n\n" and returns the UTF-16 offset at which each page
    /// starts (element i = start of page i+1; page 1 starts at 0). Phase 7 uses
    /// these to assign chunk page numbers after the PDF is discarded.
    func joined() -> (text: String, pageBreaks: [Int]) {
        var text = ""
        var breaks: [Int] = []
        for (index, page) in pages.enumerated() {
            breaks.append(text.utf16.count)
            text += page.text
            if index < pages.count - 1 { text += "\n\n" }
        }
        return (text, breaks)
    }

    /// Page number (1-based) for a UTF-16 offset into the joined text, or nil for
    /// non-paginated documents.
    static func pageNumber(for utf16Offset: Int, pageBreaks: [Int]) -> Int? {
        guard !pageBreaks.isEmpty else { return nil }
        var page = 1
        for (index, start) in pageBreaks.enumerated() where utf16Offset >= start {
            page = index + 1
        }
        return page
    }
}
