import Testing
import UIKit
@testable import EchoMind

@Suite struct PDFTextExtractorTests {
    private func textPDF(pages: [String]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                (page as NSString).draw(in: CGRect(x: 40, y: 40, width: 520, height: 700),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
    }

    private func scannedPDF() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
        }
    }

    @Test func extractsTextAndPageCount() throws {
        let longText = "This is a page of real text content that comfortably exceeds the scanned threshold for detection purposes."
        let data = textPDF(pages: [longText, longText + " Page two."])
        let extracted = try PDFTextExtractor().extract(data: data)
        #expect(extracted.pageCount == 2)
        #expect(extracted.pages.count == 2)
        #expect(extracted.pages[0].text.contains("real text content"))
    }

    @Test func rejectsScannedPDF() {
        let data = scannedPDF()
        #expect(throws: ImportError.scannedPDF) {
            _ = try PDFTextExtractor().extract(data: data)
        }
    }

    @Test func rejectsUnreadableData() {
        #expect(throws: (any Error).self) {
            _ = try PDFTextExtractor().extract(data: Data("not a pdf".utf8))
        }
    }
}
