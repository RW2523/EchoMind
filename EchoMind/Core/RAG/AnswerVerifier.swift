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

    /// Acronym expansions asserted in the answer ("HHL stands for …") that the
    /// context does not support. The number check can't see this failure — field
    /// bug: "HHL stands for Hybrid Least Squares" for a paper that says
    /// Harrow–Hassidim–Lloyd. An expansion is unsupported when NO leading run of
    /// its significant words both spells the acronym AND occurs contiguously in
    /// the context. Prefix-based on purpose: commas inside a correct expansion
    /// ("Harrow, Hassidim and Lloyd" — the paper's own wording) and trailing
    /// clauses ("… and it solves linear systems") must not cause false flags.
    static func unsupportedExpansions(answer: String, context: String) -> [String] {
        let normalizedContext = significantPhrase(context)
        var bad: [String] = []
        for phrase in ["stands for", "is short for", "is an abbreviation for"] {
            var search = answer[answer.startIndex...]
            while let range = search.range(of: phrase) {
                let beforeText = answer[..<range.lowerBound]
                search = answer[range.upperBound...]
                // Word boundary: "stands for" must not match inside "stands
                // formally". The phrase always ends mid-sentence, so the next
                // character (if any) can't be a letter.
                if range.upperBound < answer.endIndex, answer[range.upperBound].isLetter { continue }
                // The expansion must start right after the phrase ("stands for,
                // then…" asserts nothing), and runs to a sentence-hard
                // terminator — a comma is legal INSIDE an expansion ("Harrow,
                // Hassidim and Lloyd"), so it must not truncate what we inspect.
                let remainder = answer[range.upperBound...].drop(while: { $0 == " " })
                let after = remainder.split(whereSeparator: { $0 == "." || $0 == ";" || $0 == "(" || $0 == "\n" })
                // The acronym is the last whitespace token, edge punctuation
                // trimmed — splitting on hyphens would truncate "3D-CNN" to "CNN".
                let acronym = beforeText.split(whereSeparator: { $0.isWhitespace }).last
                    .map { String($0).trimmingCharacters(in: CharacterSet.alphanumerics.inverted) } ?? ""
                guard let lead = remainder.first,
                      lead.isLetter || lead.isNumber || "\"'“‘".contains(lead),
                      acronym.count >= 2, acronym == acronym.uppercased(),
                      acronym.contains(where: \.isLetter),          // "45 stands for…" isn't an acronym
                      let expansion = after.first.map({ String($0).trimmingCharacters(in: .whitespaces) }),
                      !expansion.isEmpty else { continue }
                let words = Array(expansion.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init).prefix(12))
                let significant = words.filter { !Self.stopwords.contains($0.lowercased()) }
                guard !significant.isEmpty else { continue }
                // Supported when a leading run of the expansion (a) appears
                // contiguously in the context AND (b) spells the acronym —
                // initials computed both with and without stopwords, so
                // "POW = prisoner of war" works — or (c) the FULL expansion
                // appears verbatim in the context even if the initials don't
                // spell it (non-initialisms like "ID is short for
                // identification"): the document saying it is support enough.
                let acronymLower = acronym.lowercased()
                let fullPhrase = significantPhrase(significant.joined(separator: " "))
                let supported = normalizedContext.contains(fullPhrase)
                    || (1...words.count).contains { length in
                        let candidate = Array(words.prefix(length))
                        let allInitials = candidate.compactMap { $0.first.map(String.init) }
                            .joined().lowercased()
                        let sigInitials = candidate.filter { !Self.stopwords.contains($0.lowercased()) }
                            .compactMap { $0.first.map(String.init) }.joined().lowercased()
                        return (allInitials == acronymLower || sigInitials == acronymLower)
                            && normalizedContext.contains(significantPhrase(candidate.joined(separator: " ")))
                    }
                if !supported {
                    let reported = significant.prefix(max(acronym.count, 1)).joined(separator: " ")
                    bad.append("\(acronym) = \(reported)")
                }
            }
        }
        return bad
    }

    private static let stopwords: Set<String> = ["of", "for", "and", "the", "in", "on", "to", "a", "an"]

    /// Case- and diacritic-folded significant words (stopwords dropped, naive
    /// plural 's' trimmed) joined by single spaces, space-padded — so
    /// "Harrow-Hassidim-Lloyd" and "Harrow, Hassidim and Lloyd" reduce to the
    /// same contiguous phrase, and "Networks" matches "network".
    private static func significantPhrase(_ text: String) -> String {
        " " + text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
            .filter { !stopwords.contains($0) }
            .map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
            .joined(separator: " ") + " "
    }
}
