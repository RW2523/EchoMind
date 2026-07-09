import Foundation

/// Turns a growing (cumulative) answer stream into complete sentences the moment
/// each one finishes (Voice Agent V2). This is what makes the agent feel fast:
/// TTS speaks sentence 1 while the model is still generating sentence 3. Pure and
/// deterministic — fed cumulative snapshots, it returns only the *newly* completed
/// sentences and holds the trailing partial until `flush()`.
nonisolated struct SentenceChunker {
    private var consumed = 0        // chars already returned as sentences
    private var lastText = ""

    /// Feed the latest cumulative text; get back any sentences completed since the
    /// previous call. A sentence is "complete" only when a terminator is followed
    /// by more text (so we never emit a fragment the next token might extend).
    mutating func push(cumulative text: String) -> [String] {
        lastText = text
        let chars = Array(text)
        guard consumed <= chars.count else { consumed = chars.count; return [] }

        var sentences: [String] = []
        var start = consumed
        var i = consumed
        while i < chars.count {
            if Self.isTerminator(chars[i]),
               i + 1 < chars.count,                       // something follows → sentence ended
               Self.followsBoundary(chars, after: i),
               !Self.isAbbreviationOrDecimal(chars, dotIndex: i) {
                let sentence = String(chars[start...i]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                consumed = i + 1
                start = i + 1
            }
            i += 1
        }
        return sentences
    }

    /// Call once the stream ends: returns the trailing sentence/partial, if any.
    mutating func flush() -> String? {
        let chars = Array(lastText)
        guard consumed < chars.count else { return nil }
        let tail = String(chars[consumed...]).trimmingCharacters(in: .whitespacesAndNewlines)
        consumed = chars.count
        return tail.isEmpty ? nil : tail
    }

    // MARK: - Boundary heuristics

    private static func isTerminator(_ c: Character) -> Bool { c == "." || c == "!" || c == "?" }

    /// The terminator ends a sentence only if the next char is whitespace (or a
    /// closing quote/paren then whitespace).
    private static func followsBoundary(_ chars: [Character], after i: Int) -> Bool {
        var j = i + 1
        while j < chars.count, chars[j] == "\"" || chars[j] == ")" || chars[j] == "'" || chars[j] == "”" {
            j += 1
        }
        return j >= chars.count || chars[j] == " " || chars[j] == "\n"
    }

    /// Guards against splitting decimals ("3.5"), initials ("J. Smith"), dotted
    /// abbreviations ("e.g.", "U.S."), and common titles ("Mr.", "Dr.").
    private static func isAbbreviationOrDecimal(_ chars: [Character], dotIndex i: Int) -> Bool {
        guard chars[i] == "." else { return false }        // only '.' is ambiguous
        // Decimal: digit . digit
        if i > 0, i + 1 < chars.count, chars[i - 1].isNumber, chars[i + 1].isNumber { return true }
        // Dotted abbreviation like e.g. / U.S. (a '.' two chars back)
        if i >= 2, chars[i - 2] == "." { return true }
        // Preceding word
        var j = i - 1
        var word = ""
        while j >= 0, chars[j].isLetter { word.insert(chars[j], at: word.startIndex); j -= 1 }
        if word.count == 1, word.first!.isUppercase { return true }   // initial
        let titles: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "no", "fig", "al", "approx"]
        return titles.contains(word.lowercased())
    }
}
