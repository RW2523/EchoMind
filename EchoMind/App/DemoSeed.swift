import Foundation

#if DEBUG
/// DEBUG-only rich demo data for App Store screenshots, triggered by `--demo-seed`.
/// Seeds realistic sessions (with reports, categories, action items, continuity),
/// long-term memory facts, and an Ask conversation — so every screen shows a
/// populated, compelling state. Idempotent: only seeds when there are no sessions.
enum DemoSeed {
    /// Must match `AskViewModel`'s single-conversation id.
    static let conversationId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!

    static func runIfRequested(_ deps: AppDependencies) async {
        guard CommandLine.arguments.contains("--demo-seed") else { return }
        if let existing = try? await deps.sessionRepository.fetchAll(), !existing.isEmpty { return }

        await seedSessions(deps)
        await seedMemory(deps)
        await seedChat(deps)
    }

    // MARK: - Sessions

    private struct Line { let speaker: String; let text: String; let start: TimeInterval }

    private static func seedSessions(_ deps: AppDependencies) async {
        await session(deps, title: "Product Weekly — Phoenix", daysAgo: 1, minutes: 32,
                      category: "Product Weekly", topics: ["Roadmap", "Launch"],
                      summary: MeetingSummary(
                        overview: "The team reviewed Project Phoenix ahead of the Q3 launch. Beta feedback is strong; the onboarding redesign is the main open risk.",
                        keyDecisions: ["Ship the Phoenix beta to 500 users this Friday",
                                       "Freeze new features two weeks before launch"],
                        actionItems: [.init(text: "Prepare the release notes", owner: "Sam"),
                                      .init(text: "Finalize the onboarding copy", owner: "Priya"),
                                      .init(text: "Set up crash monitoring", owner: nil)],
                        risks: ["Onboarding redesign may slip", "App Review timing is tight"],
                        openQuestions: ["Do we need a marketing push at launch?"]),
                      actionStates: [true, false, false],
                      continuity: ["Follow-up on last week's decision to target a Q3 launch.",
                                   "The onboarding redesign flagged last meeting is now owned by Sam."],
                      transcript: [
                        Line(speaker: "Speaker 1", text: "Beta numbers look great — retention is up 12% this week.", start: 3),
                        Line(speaker: "Speaker 2", text: "Let's ship the beta to five hundred users on Friday.", start: 41),
                        Line(speaker: "Speaker 1", text: "Sam, can you own the release notes? Priya takes onboarding copy.", start: 88),
                      ])

        await session(deps, title: "1:1 with Priya", daysAgo: 3, minutes: 24,
                      category: "1:1", topics: ["Security", "Growth"],
                      summary: MeetingSummary(
                        overview: "Career check-in with Priya, who leads the security team. Discussed the encryption rollout and next-quarter goals.",
                        keyDecisions: ["Priya will lead the security review for Phoenix"],
                        actionItems: [.init(text: "Draft the encryption rollout plan", owner: "Priya")],
                        risks: [], openQuestions: ["Headcount for the security team next quarter?"]),
                      actionStates: [false],
                      continuity: [],
                      transcript: [
                        Line(speaker: "Speaker 1", text: "The encryption work is on track for next month.", start: 5),
                      ])

        await session(deps, title: "Design Review — Onboarding", daysAgo: 5, minutes: 45,
                      category: "Design Review", topics: ["Onboarding", "UX"],
                      summary: MeetingSummary(
                        overview: "Reviewed the new onboarding flow. The three-screen version tested best; ship it behind a flag.",
                        keyDecisions: ["Adopt the three-screen onboarding"],
                        actionItems: [.init(text: "Build the onboarding behind a feature flag", owner: "Sam")],
                        risks: ["First-run drop-off if copy is too long"], openQuestions: []),
                      actionStates: [false], continuity: [],
                      transcript: [Line(speaker: "Speaker 1", text: "The shorter flow converts noticeably better.", start: 4)])

        await session(deps, title: "Customer Call — Acme", daysAgo: 6, minutes: 38,
                      category: "Customer Call", topics: ["Renewal", "Feedback"],
                      summary: MeetingSummary(
                        overview: "Acme is happy with reliability and wants SSO before renewal. Renewal likely if SSO lands in Q3.",
                        keyDecisions: ["Prioritize SSO for the Acme renewal"],
                        actionItems: [.init(text: "Scope SSO effort", owner: "Sam")],
                        risks: ["Renewal at risk without SSO"], openQuestions: []),
                      actionStates: [false], continuity: [],
                      transcript: [Line(speaker: "Speaker 2", text: "We'd renew today if you had SSO.", start: 6)])

        await session(deps, title: "Product Weekly — Phoenix", daysAgo: 9, minutes: 30,
                      category: "Product Weekly", topics: ["Roadmap"],
                      summary: MeetingSummary(
                        overview: "Set the Q3 launch target for Project Phoenix and identified onboarding as the top risk to resolve.",
                        keyDecisions: ["Target Q3 for the Phoenix launch"],
                        actionItems: [.init(text: "Assign an owner to the onboarding redesign", owner: nil)],
                        risks: ["Onboarding redesign unassigned"], openQuestions: []),
                      actionStates: [true], continuity: [],
                      transcript: [Line(speaker: "Speaker 1", text: "Let's lock Q3 for the launch.", start: 5)])
    }

    private static func session(_ deps: AppDependencies, title: String, daysAgo: Int, minutes: Int,
                                category: String, topics: [String], summary: MeetingSummary,
                                actionStates: [Bool], continuity: [String], transcript: [Line]) async {
        let id = UUID()
        let created = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        let repo = deps.sessionRepository
        try? await repo.create(SessionSnapshot(id: id, title: title, createdAt: created,
                                               updatedAt: created, duration: Double(minutes) * 60, origin: .live))
        for (i, line) in transcript.enumerated() {
            try? await repo.appendSegment(
                SegmentSnapshot(sessionId: id, text: line.text, startTime: line.start,
                                endTime: line.start + 12, speakerLabel: line.speaker),
                toSession: id)
            _ = i
        }
        if let json = try? String(decoding: JSONEncoder().encode(summary), as: UTF8.self) {
            try? await repo.setReport(summaryJSON: json, sessionId: id)
        }
        try? await repo.setTags([category] + topics, sessionId: id)
        if !actionStates.isEmpty, let j = try? String(decoding: JSONEncoder().encode(actionStates), as: UTF8.self) {
            try? await repo.setActionStates(j, sessionId: id)
        }
        if !continuity.isEmpty, let j = try? String(decoding: JSONEncoder().encode(continuity), as: UTF8.self) {
            try? await repo.setContinuity(j, sessionId: id)
        }
    }

    // MARK: - Memory + chat

    private static func seedMemory(_ deps: AppDependencies) async {
        let now = Date()
        let facts: [MemoryFactSnapshot] = [
            .init(id: UUID(), kind: .person, text: "Priya Nair leads the security team", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-100)),
            .init(id: UUID(), kind: .project, text: "Project Phoenix launches in Q3", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-200)),
            .init(id: UUID(), kind: .decision, text: "The Phoenix beta ships to 500 users first", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-300)),
            .init(id: UUID(), kind: .person, text: "Sam owns the onboarding redesign", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-400)),
            .init(id: UUID(), kind: .recurring, text: "Product Weekly happens every Tuesday", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-500)),
            .init(id: UUID(), kind: .preference, text: "The team freezes features two weeks before launch", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-600)),
            .init(id: UUID(), kind: .decision, text: "Acme's renewal depends on shipping SSO", sourceSessionId: nil, updatedAt: now.addingTimeInterval(-700)),
        ]
        try? await deps.memoryStore.add(facts)
    }

    private static func seedChat(_ deps: AppDependencies) async {
        let messages: [(MessageRole, String)] = [
            (.user, "What did we decide about the Phoenix launch?"),
            (.assistant, "You decided to ship the Phoenix beta to 500 users this Friday, and to freeze new features two weeks before the Q3 launch."),
            (.user, "Who's handling onboarding?"),
            (.assistant, "Sam owns the onboarding redesign — it was flagged as the main launch risk in your last Product Weekly."),
        ]
        var t = Date().addingTimeInterval(-600)
        for (role, content) in messages {
            try? await deps.chatRepository.append(
                ChatMessageSnapshot(conversationId: conversationId, role: role, content: content, createdAt: t))
            t = t.addingTimeInterval(30)
        }
    }
}
#endif
