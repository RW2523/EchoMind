import Foundation

/// Deterministic grounding check for generated answers (anti-confabulation).
///
/// The failure it kills, verbatim from field testing: the model answered a
/// dataset question with "22,000 frames split 9,000 each" when the document said
/// 5,800 clips split 5,000/400/400 — the "22" bled over from "22 parking
/// locations" nearby. LLMs fabricate *plausible* numbers; a grounded answer's
/// figures must exist in the retrieved passages (or the question itself).
/// Violations trigger one corrective retry, then an honest caveat — never a
/// silently wrong figure.
nonisolated enum AnswerVerifier {
    /// Digit-bearing tokens, canonicalized: thousands separators stripped
    /// ("5,800" → "5800"), decimal trailing zeros trimmed ("5.50" → "5.5",
    /// "5.0" → "5"), leading zeros dropped ("09" → "9"), unit suffixes dropped
    /// ("30fps" → "30", "5s" → "5"), sign/percent ignored.
    static func numbers(in text: String) -> Set<String> {
        var found: Set<String> = []
        var current = ""
        func flush() {
            guard current.contains(where: \.isNumber) else { current = ""; return }
            // trim non-numeric edges, strip separators
            var token = current.trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            token = token.replacingOccurrences(of: ",", with: "")
            if token.contains(".") {
                while token.hasSuffix("0") { token = String(token.dropLast()) }
                if token.hasSuffix(".") { token = String(token.dropLast()) }
            }
            while token.count > 1, token.hasPrefix("0"), !token.hasPrefix("0.") {
                token = String(token.dropFirst())
            }
            if !token.isEmpty { found.insert(token) }
            current = ""
        }
        for character in text {
            if character.isNumber || ((character == "." || character == ",") && !current.isEmpty) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return found
    }

    /// Numbers in `answer` with no support in the retrieved context, the
    /// question, or `extraAllowed` sources (known-facts block, earlier USER
    /// turns — figures the app itself supplied or the user stated are not
    /// fabrications; only assistant history stays distrusted). Sorted for
    /// stable messages/tests.
    static func unsupportedNumbers(answer: String, context: String, question: String,
                                   extraAllowed: [String] = []) -> [String] {
        var allowed = numbers(in: context).union(numbers(in: question))
        for source in extraAllowed { allowed.formUnion(numbers(in: source)) }
        return numbers(in: answer).subtracting(allowed).sorted()
    }
}
