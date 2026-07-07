import Foundation

#if DEBUG
/// Deterministic ~9,000-word fixture transcript (§5.7). Generated in code (no
/// bundled assets, byte-identical runs) with embedded ground truth so summaries
/// can be eyeballed and the plan asserted exactly.
nonisolated enum DebugFixtures {
    static let groundTruthDecision = "Decision D3: move the billing migration to Q3 to reduce launch risk."
    static let groundTruthOwner = "Priya owns the vendor security audit and will report back by Friday."
    static let groundTruthRisk = "Risk: the analytics vendor contract expires before the migration completes."
    static let groundTruthQuestion = "Open question: do we need a data-processing addendum for the EU region?"

    // A realistic sample document to seed the Knowledge tab for testing Ask.
    static let sampleDocumentTitle = "Company Handbook"
    static let sampleDocumentText = """
    # Company Handbook

    ## Refund Policy
    Customers may request a refund within 30 days of purchase. Refunds are processed \
    within 5 business days to the original payment method. Digital goods are \
    non-refundable once downloaded.

    ## Support Hours
    Customer support is available Monday through Friday, 9am to 6pm Pacific Time. \
    Priority support customers also get weekend coverage.

    ## Vacation Policy
    Full-time employees accrue 20 days of paid vacation per year, plus 10 company \
    holidays. Unused vacation rolls over up to a maximum of 5 days.

    ## Security
    All company laptops must use full-disk encryption. Priya Nair leads the security \
    team and runs the quarterly vendor security audit. Report incidents to \
    security@example.com within 24 hours.
    """

    private static let topics = [
        "the onboarding funnel", "quarterly revenue", "the billing migration",
        "customer churn", "the mobile roadmap", "infrastructure costs",
        "the security audit", "hiring plans", "the analytics pipeline", "support volume",
    ]

    /// ~150 segments × ~60 words ≈ 9,000 words. Timestamps advance ~6s each.
    static func meetingSegments(count: Int = 150) -> [SegmentText] {
        var segments: [SegmentText] = []
        var time: TimeInterval = 0
        for index in 0..<count {
            segments.append(SegmentText(text: line(for: index), startTime: time, endTime: time + 6))
            time += 6
        }
        return segments
    }

    private static func line(for index: Int) -> String {
        switch index {
        case 10: return groundTruthDecision
        case 25: return groundTruthOwner
        case 40: return groundTruthRisk
        case 60: return groundTruthQuestion
        default:
            let topic = topics[index % topics.count]
            return "The team discussed \(topic) in detail during this part of the meeting, "
                + "weighing tradeoffs around latency, cost, reliability, and customer impact. "
                + "Several people shared data from the last two weeks and compared it against the "
                + "targets set in the previous planning session. They agreed the numbers were moving "
                + "in the right direction but flagged a few areas that still need attention before the "
                + "next review, and decided to follow up with the relevant owners next week."
        }
    }
}
#endif
