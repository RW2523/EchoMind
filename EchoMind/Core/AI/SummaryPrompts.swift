import Foundation

// Budget arithmetic (PLAN.md §3, §5.3) — enforced, not aspirational:
//
//  Call    | Input                                           | Out  | Total  | Headroom/4096
//  Map     | map instr ≤150 + window ≤2,200                  | 300  | ≤2,650 | ≥1,446 (~35%)
//  Reduce  | reduce instr ~200 + schema ~150 + partials≤2,150| 700  | ≤3,200 | ≥896 (~22%)
//
// Max partials per reduce: (2,500 − 200 − 150) / 300 ≈ 7 → one reduce covers
// ~7 × 2,200 ≈ 15,400 input tokens ≈ ~90 min of speech. Beyond that: intermediate
// reduce (merge partials in groups of ≤7, then reduce).

nonisolated enum SummaryPrompts {
    static let map = """
    You are summarizing one part of a meeting transcript. Write concise plain-text \
    bullet points capturing decisions, action items (with the responsible person if \
    named), risks, and open questions. Preserve names, numbers, and dates VERBATIM. \
    Do not add a preamble or conclusion — bullets only.
    """

    static let reduce = """
    You are producing a structured summary of a meeting from partial notes. Merge the \
    notes into the required fields without repeating yourself. Preserve names, numbers, \
    dates, and decisions verbatim. Only set an action item's owner when a specific \
    person is explicitly named; otherwise leave it empty.
    """

    // Budgets (tokens).
    static let mapOutputTokens = 300
    static let reduceOutputTokens = 700
    static let windowTokenLimit = 2_200
    static let reduceInputBudget = 2_500
    static let reduceInstructionsReserve = 200
    static let schemaOverhead = 150
    /// A single window ≤ this runs the skip-map shortcut; above it runs map→reduce.
    static let skipMapEligibleBudget = 2_150   // 2,500 − 200 − 150
    static let maxPartialsPerReduce = 7
}
