import Testing
@testable import EchoMind

@Suite struct ExtractedTextTests {
    @Test func joinedComputesPageBreaks() {
        let extracted = ExtractedText(pages: [
            ExtractedPage(pageNumber: 1, text: "Page one text"),
            ExtractedPage(pageNumber: 2, text: "Page two text"),
            ExtractedPage(pageNumber: 3, text: "Third"),
        ], pageCount: 3)
        let (text, breaks) = extracted.joined()
        #expect(breaks.count == 3)
        #expect(breaks[0] == 0)
        #expect(text.contains("Page one text"))
        #expect(text.contains("Page two text"))
        // Each break offset lands at the start of that page's text.
        let utf16 = Array(text.utf16)
        for (index, start) in breaks.enumerated() {
            let pageStart = String(utf16: Array(utf16[start...]))
            #expect(pageStart.hasPrefix(extracted.pages[index].text))
        }
    }

    @Test func pageNumberForOffsetRecoversPage() {
        let extracted = ExtractedText(pages: [
            ExtractedPage(pageNumber: 1, text: "AAAA"),
            ExtractedPage(pageNumber: 2, text: "BBBB"),
            ExtractedPage(pageNumber: 3, text: "CCCC"),
        ], pageCount: 3)
        let (_, breaks) = extracted.joined()
        #expect(ExtractedText.pageNumber(for: 0, pageBreaks: breaks) == 1)
        #expect(ExtractedText.pageNumber(for: breaks[1], pageBreaks: breaks) == 2)
        #expect(ExtractedText.pageNumber(for: breaks[2] + 2, pageBreaks: breaks) == 3)
    }

    @Test func nonPaginatedHasNilPageNumber() {
        #expect(ExtractedText.pageNumber(for: 5, pageBreaks: []) == nil)
    }
}

private extension String {
    init(utf16 units: [UTF16.CodeUnit]) {
        self = String(decoding: units, as: UTF16.self)
    }
}
