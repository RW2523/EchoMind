import Foundation

nonisolated enum IndexingEvent: Sendable {
    case progress(sourceId: UUID, fraction: Double)
    case finished(sourceId: UUID)
    case failed(sourceId: UUID, message: String)
}

nonisolated protocol IndexerService: Sendable {
    func indexDocument(id: UUID) async throws
    func indexSession(id: UUID) async throws
    func rebuildAll() async throws
    nonisolated var events: AsyncStream<IndexingEvent> { get }
}

/// chunk -> embed (batched) -> pack -> store KnowledgeChunks (§6.3). Idempotent:
/// deletes existing chunks for the source first, so re-index never duplicates.
/// Document status is persisted; session status is ephemeral via `events`.
actor RAGIndexer: IndexerService {
    nonisolated let events: AsyncStream<IndexingEvent>
    private let eventContinuation: AsyncStream<IndexingEvent>.Continuation

    private let documents: any DocumentRepository
    private let sessions: any SessionRepository
    private let chunks: any ChunkRepository
    private let embedder: any EmbeddingService
    private let chunker: any TextChunking

    init(documents: any DocumentRepository,
         sessions: any SessionRepository,
         chunks: any ChunkRepository,
         embedder: any EmbeddingService,
         chunker: any TextChunking = TextChunker()) {
        self.documents = documents
        self.sessions = sessions
        self.chunks = chunks
        self.embedder = embedder
        self.chunker = chunker
        (events, eventContinuation) = AsyncStream<IndexingEvent>.makeStream()
    }

    func indexDocument(id: UUID) async throws {
        guard let document = try await documents.fetchDocument(id: id) else { return }
        do {
            try await documents.updateStatus(id: id, status: .indexing)
            try await chunks.deleteChunks(sourceId: id, sourceType: .document)
            let pageBreaks = document.pageBreaks.enumerated()
                .map { (pageNumber: $0.offset + 1, utf16Offset: $0.element) }
            let textChunks = chunker.chunk(document: document.textContent,
                                           pageBreaks: pageBreaks, sourceId: id)
            try await embedAndStore(textChunks, sourceId: id)
            try await documents.updateStatus(id: id, status: .ready)
            eventContinuation.yield(.finished(sourceId: id))
        } catch {
            try? await documents.updateStatus(id: id, status: .failed)
            eventContinuation.yield(.failed(sourceId: id, message: String(describing: error)))
            throw error
        }
    }

    func indexSession(id: UUID) async throws {
        let segments = try await sessions.fetchSegments(sessionId: id)
        guard !segments.isEmpty else { eventContinuation.yield(.finished(sourceId: id)); return }
        do {
            try await chunks.deleteChunks(sourceId: id, sourceType: .session)
            let tuples = segments.map { (text: $0.text, startTime: $0.startTime) }
            let textChunks = chunker.chunk(segments: tuples, sourceId: id)
            try await embedAndStore(textChunks, sourceId: id)
            eventContinuation.yield(.finished(sourceId: id))
        } catch {
            eventContinuation.yield(.failed(sourceId: id, message: String(describing: error)))
            throw error
        }
    }

    func rebuildAll() async throws {
        try await chunks.deleteAll()
        for document in (try? await documents.fetchAll()) ?? [] {
            try Task.checkCancellation()
            try? await indexDocument(id: document.id)
        }
        for session in (try? await sessions.recentSessions(limit: nil)) ?? [] {
            try Task.checkCancellation()
            try? await indexSession(id: session.id)
        }
    }

    // MARK: - Helpers

    private func embedAndStore(_ textChunks: [TextChunk], sourceId: UUID) async throws {
        guard !textChunks.isEmpty else { return }
        try Task.checkCancellation()
        let vectors = try await embedder.embed(textChunks.map(\.text))
        var snapshots: [ChunkSnapshot] = []
        snapshots.reserveCapacity(textChunks.count)
        for (index, chunk) in textChunks.enumerated() {
            let packed = index < vectors.count ? VectorPacking.pack(vectors[index]) : Data()
            snapshots.append(ChunkSnapshot(sourceId: chunk.sourceId, sourceType: chunk.sourceType,
                                           text: chunk.text, embedding: packed, chunkIndex: chunk.chunkIndex,
                                           pageNumber: chunk.pageNumber, timestamp: chunk.timestamp))
            eventContinuation.yield(.progress(sourceId: sourceId,
                                              fraction: Double(index + 1) / Double(textChunks.count)))
        }
        try await chunks.insert(snapshots)
    }
}
