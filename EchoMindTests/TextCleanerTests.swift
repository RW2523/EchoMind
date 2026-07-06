import Testing
import Foundation
@testable import EchoMind

@Suite struct TextCleanerTests {
    @Test func repairsHyphenatedLineBreaks() {
        #expect(TextCleaner.clean("exam-\nple") == "example")
        #expect(TextCleaner.clean("multi-\n  ple words") == "multiple words")
    }

    @Test func preservesLegitimateHyphens() {
        #expect(TextCleaner.clean("V1-only feature") == "V1-only feature")
        // Uppercase continuation is NOT joined (proper noun after a break).
        #expect(TextCleaner.clean("New-\nYork").contains("New") == true)
    }

    @Test func normalizesCRLF() {
        #expect(TextCleaner.clean("a\r\nb\rc") == "a\nb\nc")
    }

    @Test func collapsesSpacesAndBlankLines() {
        #expect(TextCleaner.clean("a    b") == "a b")
        #expect(TextCleaner.clean("a\n\n\n\nb") == "a\n\nb")
        #expect(TextCleaner.clean("trailing   \nspace") == "trailing\nspace")
    }

    @Test func stripsControlCharacters() {
        #expect(TextCleaner.clean("x\u{0000}y") == "xy")
        #expect(TextCleaner.clean("a\u{0007}b") == "ab")
    }
}
