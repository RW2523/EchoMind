import Foundation

/// Pure text cleaning for imported documents (§4.3 step 5). Order matters.
nonisolated enum TextCleaner {
    static func clean(_ input: String) -> String {
        var text = input

        // CRLF / CR -> LF
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        // Strip Unicode control chars except \n and \t.
        text = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || scalar.properties.generalCategory != .control
        }))

        // Repair hyphenated line breaks: "exam-\nple" -> "example" (lowercase
        // continuation only, so "V1-only" and "well-known\nX" survive).
        text = text.replacingOccurrences(of: "([A-Za-z])-\\s*\\n\\s*([a-z])",
                                         with: "$1$2", options: .regularExpression)

        // Collapse space/tab runs.
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        // Trim trailing whitespace before newlines.
        text = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        // Collapse 3+ newlines to 2.
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
