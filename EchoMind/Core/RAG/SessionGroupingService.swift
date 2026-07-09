import Foundation

/// Orchestrates AI meeting grouping (R2): build a vector per session from its
/// stored chunk embeddings, cluster them, and give each cluster a canonical
/// category name (reused across members so similar meetings don't fragment). The
/// category lands in `Session.tags[0]`; topic tags follow. Runs after a report so
/// it always has fresh content; cheap because clustering is pure and embeddings
/// already exist (one small classify call per *new* cluster only).
nonisolated protocol SessionGrouping: Sendable {
    func organize() async
}

nonisolated struct SessionGroupingService: SessionGrouping {
    let sessions: any SessionRepository
    let chunks: any ChunkRepository
    let embedder: any EmbeddingService
    let classifier: any MeetingClassifying
    let clusterer: SessionClusterer

    init(sessions: any SessionRepository, chunks: any ChunkRepository, embedder: any EmbeddingService,
         classifier: any MeetingClassifying, clusterer: SessionClusterer = SessionClusterer()) {
        self.sessions = sessions
        self.chunks = chunks
        self.embedder = embedder
        self.classifier = classifier
        self.clusterer = clusterer
    }

    func organize() async {
        let allSessions = (try? await sessions.fetchAll()) ?? []
        guard !allSessions.isEmpty, let dim = try? await embedder.dimension, dim > 0 else { return }
        let allChunks = (try? await chunks.fetchAll()) ?? []

        var vectorsBySession: [UUID: [[Float]]] = [:]
        for chunk in allChunks where chunk.sourceType == .session {
            if let v = try? VectorPacking.unpack(chunk.embedding, expectedDimension: dim) {
                vectorsBySession[chunk.sourceId, default: []].append(v)
            }
        }

        let sessionVectors = allSessions.compactMap { session -> SessionVector? in
            guard let vs = vectorsBySession[session.id], let mean = ClusterMath.meanNormalized(vs) else { return nil }
            return SessionVector(id: session.id, vector: mean)
        }
        guard !sessionVectors.isEmpty else { return }

        let clusters = clusterer.cluster(sessionVectors)
        let byID = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id, $0) })

        for cluster in clusters {
            // Canonical name: if any member is already categorised, reuse it.
            let existing = cluster.memberIDs.compactMap { byID[$0]?.tags.first }.first { !$0.isEmpty }
            let category: MeetingCategory
            if let existing {
                category = MeetingCategory(category: existing, topics: [])
            } else {
                let overview = cluster.memberIDs.compactMap { byID[$0].flatMap(Self.overview) }.first
                    ?? cluster.memberIDs.first.flatMap { byID[$0]?.title } ?? "Meeting"
                category = (try? await classifier.classify(overview: overview, existingName: nil))
                    ?? MeetingCategory(category: "General", topics: [])
            }
            for id in cluster.memberIDs where (byID[id]?.tags.first ?? "").isEmpty {
                try? await sessions.setTags([category.category] + category.topics, sessionId: id)
            }
        }
    }

    private static func overview(_ session: SessionSnapshot) -> String? {
        guard let json = session.summaryJSON,
              let summary = try? JSONDecoder().decode(MeetingSummary.self, from: Data(json.utf8)),
              !summary.overview.isEmpty else { return nil }
        return summary.overview
    }
}
