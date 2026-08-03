import Foundation

/// Exactly-once integration of finalized transcript lines (Live Transcript fix).
/// SpeechAnalyzer finals normally arrive once per utterance range, but a replayed
/// or misclassified result shows up as an OVERLAP of the last accepted line: the
/// same speech delivered twice. Decision rules:
/// - disjoint in time (new starts at/after last end, small tolerance) → append
/// - overlapping and the new text extends the last → replaceLast (refinement)
/// - overlapping and the new text is the same / a stale shorter snapshot → drop
/// - overlapping but genuinely different words → append (NEVER lose speech)
nonisolated enum TranscriptAssembly {
    enum Action: Equatable {
        case append
        case replaceLast
        case drop
    }

    /// Overlap tolerance in seconds — adjacent utterances may share a boundary.
    static let boundaryTolerance: TimeInterval = 0.05

    static func action(lastText: String, lastStart: TimeInterval, lastEnd: TimeInterval,
                       newText: String, newStart: TimeInterval, newEnd: TimeInterval) -> Action {
        let overlaps = newStart < lastEnd - boundaryTolerance && newEnd > lastStart
        guard overlaps else { return .append }

        let last = normalize(lastText)
        let new = normalize(newText)
        if new == last { return .drop }                       // exact duplicate
        if last.isEmpty || new.hasPrefix(last) { return .replaceLast }   // refinement/extension
        if last.hasPrefix(new) { return .drop }               // stale shorter snapshot
        return .append                                        // different words — keep both
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
