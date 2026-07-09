import Foundation
import FoundationModels

/// Notes linking a new report to prior related meetings (R3 continuity).
@Generable
nonisolated struct ContinuityNotes: Sendable {
    @Guide(description: "Short notes connecting this meeting to the prior related ones, e.g. 'Follow-up on last week's decision to ship Friday'. Only real connections; empty if none.", .count(0...4))
    var notes: [String]

    init(notes: [String] = []) { self.notes = notes }
}

nonisolated protocol ContinuityProviding: Sendable {
    /// Continuity notes for a session given its overview, drawn from prior similar meetings.
    func continuityNotes(for sessionId: UUID, overview: String) async -> [String]
}

/// Finds the most similar EARLIER sessions (by session-vector cosine over stored
/// chunk embeddings — same signal as clustering, no extra inference) and asks the
/// model how the new meeting continues them. Bounded prior context; routed gateway.
nonisolated struct MeetingContinuityService: ContinuityProviding {
    let sessions: any SessionRepository
    let chunks: any ChunkRepository
    let embedder: any EmbeddingService
    let gateway: any ModelGateway
    var maxPriors: Int = 3
    var similarityThreshold: Float = 0.4

    private static let instruction = """
    You connect a new meeting to earlier related meetings. Given this meeting and a \
    few prior ones, return short continuity notes — follow-ups, changed decisions, \
    ongoing threads — that reference the earlier meetings. Only note genuine links; \
    return nothing if there's no real connection.
    """

    func continuityNotes(for sessionId: UUID, overview: String) async -> [String] {
        let overview = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !overview.isEmpty,
              let dim = try? await embedder.dimension, dim > 0 else { return [] }

        let allSessions = (try? await sessions.fetchAll()) ?? []
        guard let current = allSessions.first(where: { $0.id == sessionId }) else { return [] }

        var vectorsBySession: [UUID: [[Float]]] = [:]
        for chunk in ((try? await chunks.fetchAll()) ?? []) where chunk.sourceType == .session {
            if let v = try? VectorPacking.unpack(chunk.embedding, expectedDimension: dim) {
                vectorsBySession[chunk.sourceId, default: []].append(v)
            }
        }
        guard let currentVec = vectorsBySession[sessionId].flatMap(ClusterMath.meanNormalized) else { return [] }

        let priors = allSessions
            .filter { $0.id != sessionId && $0.createdAt < current.createdAt && $0.summaryJSON != nil }
            .compactMap { session -> (SessionSnapshot, Float)? in
                guard let v = vectorsBySession[session.id].flatMap(ClusterMath.meanNormalized) else { return nil }
                let sim = ClusterMath.dot(currentVec, v)
                return sim >= similarityThreshold ? (session, sim) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxPriors)

        guard !priors.isEmpty else { return [] }

        let priorText = priors.enumerated().map { index, pair in
            "Prior meeting \(index + 1) — \(pair.0.title): \(Self.overview(pair.0) ?? "(no summary)")"
        }.joined(separator: "\n")

        let prompt = """
        This meeting:
        \(overview)

        Related earlier meetings:
        \(priorText)
        """
        let result = try? await gateway.generate(instructions: Self.instruction, prompt: prompt, as: ContinuityNotes.self)
        return result?.notes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    }

    private static func overview(_ session: SessionSnapshot) -> String? {
        guard let json = session.summaryJSON,
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: Data(json.utf8)),
              !summary.overview.isEmpty else { return nil }
        return summary.overview
    }
}
