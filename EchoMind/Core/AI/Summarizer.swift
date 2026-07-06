import Foundation

nonisolated enum SummarizerProgress: Equatable, Sendable {
    case planning
    case mapping(window: Int, of: Int)
    case reducing
}

nonisolated enum SummarizerError: Error, Equatable {
    case tooLong
    case notEnoughContent
}

/// Sendable snapshot of a segment — @Model objects never cross into the
/// summarizer under Swift 6 strict concurrency (§5.5).
nonisolated struct SegmentText: Equatable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

nonisolated protocol SummarizerService: Sendable {
    func summarize(
        segments: [SegmentText],
        onProgress: @Sendable @escaping (SummarizerProgress) -> Void
    ) async throws -> MeetingSummary
}

/// Pure, unit-testable windowing on segment boundaries (§5.5).
nonisolated struct MapReducePlan: Equatable {
    let windows: [[SegmentText]]

    static func make(segments: [SegmentText], budgeter: TokenBudgeter) -> MapReducePlan {
        let limit = SummaryPrompts.windowTokenLimit
        var windows: [[SegmentText]] = []
        var current: [SegmentText] = []
        var currentTokens = 0

        for segment in segments {
            let segTokens = budgeter.tokens(in: segment.text)
            if segTokens > limit {
                if !current.isEmpty { windows.append(current); current = []; currentTokens = 0 }
                for piece in splitOversized(segment, budgeter: budgeter, limit: limit) {
                    windows.append([piece])
                }
                continue
            }
            if currentTokens + segTokens > limit && !current.isEmpty {
                windows.append(current)
                current = [segment]
                currentTokens = segTokens
            } else {
                current.append(segment)
                currentTokens += segTokens
            }
        }
        if !current.isEmpty { windows.append(current) }
        return MapReducePlan(windows: windows)
    }

    private static func splitOversized(_ segment: SegmentText, budgeter: TokenBudgeter, limit: Int) -> [SegmentText] {
        let sentences = segment.text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
        var pieces: [SegmentText] = []
        var buffer = ""
        for (index, sentence) in sentences.enumerated() {
            let fragment = sentence + (index < sentences.count - 1 ? ". " : "")
            if !buffer.isEmpty && budgeter.tokens(in: buffer + fragment) > limit {
                pieces.append(SegmentText(text: buffer, startTime: segment.startTime, endTime: segment.endTime))
                buffer = fragment
            } else {
                buffer += fragment
            }
        }
        if !buffer.isEmpty {
            pieces.append(SegmentText(text: buffer, startTime: segment.startTime, endTime: segment.endTime))
        }
        return pieces.isEmpty ? [segment] : pieces
    }
}

/// Map-reduce summarizer over `any ModelGateway` (§5.5). All budgets from
/// SummaryPrompts; overflow → re-split once → clear error.
nonisolated struct MapReduceSummarizer: SummarizerService {
    let gateway: any ModelGateway
    let budgeter: TokenBudgeter

    init(gateway: any ModelGateway, budgeter: TokenBudgeter = TokenBudgeter()) {
        self.gateway = gateway
        self.budgeter = budgeter
    }

    func summarize(
        segments: [SegmentText],
        onProgress: @Sendable @escaping (SummarizerProgress) -> Void
    ) async throws -> MeetingSummary {
        onProgress(.planning)
        let fullText = joined(segments)
        guard budgeter.tokens(in: fullText) >= 15 else { throw SummarizerError.notEnoughContent }

        let plan = MapReducePlan.make(segments: segments, budgeter: budgeter)
        try Task.checkCancellation()

        // Skip-map shortcut: single window within the reduce-eligible budget.
        if plan.windows.count == 1 {
            let windowText = joined(plan.windows[0])
            if budgeter.tokens(in: windowText) <= SummaryPrompts.skipMapEligibleBudget {
                onProgress(.reducing)
                return try await reduce(text: windowText)
            }
        }

        // Map.
        var partials: [String] = []
        for (index, window) in plan.windows.enumerated() {
            try Task.checkCancellation()
            onProgress(.mapping(window: index + 1, of: plan.windows.count))
            let partial = try await mapWindow(joined(window))
            partials.append("Part \(index + 1)/\(plan.windows.count):\n\(partial)")
        }

        try Task.checkCancellation()
        onProgress(.reducing)
        return try await reducePartials(partials)
    }

    // MARK: - Model calls

    private func mapWindow(_ text: String) async throws -> String {
        do {
            return try await gateway.respond(instructions: SummaryPrompts.map, prompt: text,
                                             maxOutputTokens: SummaryPrompts.mapOutputTokens)
        } catch ModelGatewayError.exceededContextWindow {
            var out: [String] = []
            for half in splitInHalf(text) {
                out.append(try await gateway.respond(instructions: SummaryPrompts.map, prompt: half,
                                                     maxOutputTokens: SummaryPrompts.mapOutputTokens))
            }
            return out.joined(separator: "\n")
        }
    }

    private func reduce(text: String) async throws -> MeetingSummary {
        do {
            return try await gateway.generate(instructions: SummaryPrompts.reduce, prompt: text,
                                              as: MeetingSummary.self)
        } catch ModelGatewayError.exceededContextWindow {
            throw SummarizerError.tooLong
        }
    }

    private func reducePartials(_ partials: [String]) async throws -> MeetingSummary {
        // Intermediate reduce: too many partials → merge in groups, recurse.
        if partials.count > SummaryPrompts.maxPartialsPerReduce {
            let merged = try await mergeGroups(partials, groupSize: SummaryPrompts.maxPartialsPerReduce)
            return try await reducePartials(merged)
        }
        let combined = partials.joined(separator: "\n\n")
        do {
            return try await gateway.generate(instructions: SummaryPrompts.reduce, prompt: combined,
                                              as: MeetingSummary.self)
        } catch ModelGatewayError.exceededContextWindow {
            guard partials.count > 1 else { throw SummarizerError.tooLong }
            let merged = try await mergeGroups(partials, groupSize: max(1, partials.count / 2))
            do {
                return try await gateway.generate(instructions: SummaryPrompts.reduce,
                                                  prompt: merged.joined(separator: "\n\n"),
                                                  as: MeetingSummary.self)
            } catch ModelGatewayError.exceededContextWindow {
                throw SummarizerError.tooLong
            }
        }
    }

    private func mergeGroups(_ partials: [String], groupSize: Int) async throws -> [String] {
        var merged: [String] = []
        var index = 0
        while index < partials.count {
            let group = Array(partials[index..<min(index + groupSize, partials.count)])
            merged.append(try await gateway.respond(instructions: SummaryPrompts.map,
                                                    prompt: group.joined(separator: "\n\n"),
                                                    maxOutputTokens: SummaryPrompts.mapOutputTokens))
            index += groupSize
        }
        return merged
    }

    // MARK: - Text helpers

    private func joined(_ window: [SegmentText]) -> String {
        window.map(\.text).joined(separator: " ")
    }

    private func splitInHalf(_ text: String) -> [String] {
        let sentences = text.components(separatedBy: ". ")
        guard sentences.count > 1 else {
            let mid = text.index(text.startIndex, offsetBy: text.count / 2)
            return [String(text[..<mid]), String(text[mid...])]
        }
        let mid = sentences.count / 2
        let first = sentences[..<mid].joined(separator: ". ")
        let second = sentences[mid...].joined(separator: ". ")
        return [first, second]
    }
}
