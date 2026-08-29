import Testing
import Foundation
import SwiftData
@testable import EchoMind

// RAG 2.0: scoring priors, corpus cache, adaptive-expansion parsing, citations.

@Suite struct RetrievalScoringTests {
    @Test func coverageCountsQueryTermsPresent() {
        let terms = Set(BM25.tokenize("phoenix launch friday"))
        #expect(RetrievalScoring.coverage(queryTerms: terms, text: "The Phoenix launch is Friday.") == 1.0)
        #expect(RetrievalScoring.coverage(queryTerms: terms, text: "The phoenix rises.") > 0.3)
        #expect(RetrievalScoring.coverage(queryTerms: terms, text: "Nothing related.") == 0)
        #expect(RetrievalScoring.coverage(queryTerms: [], text: "anything") == 0)
    }

    @Test func recencyBoostsNewerButNeverDominates() {
        let now = Date()
        let fresh = RetrievalScoring.adjusted(fused: 0.02, createdAt: now, now: now, coverage: 0)
        let old = RetrievalScoring.adjusted(fused: 0.02, createdAt: now.addingTimeInterval(-400 * 86_400),
                                            now: now, coverage: 0)
        #expect(fresh > old)
        // A clearly better fused score still beats maximum recency + coverage boost:
        let boostedWorse = RetrievalScoring.adjusted(fused: 1.0 / 61, createdAt: now, now: now, coverage: 1)
        let plainBetter = RetrievalScoring.adjusted(
            fused: 2.0 / 61, createdAt: now.addingTimeInterval(-400 * 86_400), now: now, coverage: 0)
        #expect(plainBetter > boostedWorse)   // priors tie-break, relevance decides
    }

    @Test func weakDetectorRequiresBothKeywordAndSemanticMiss() {
        #expect(RetrievalScoring.isWeak(bestCosine: 0.1, bm25Hits: 0))    // true miss
        #expect(RetrievalScoring.isWeak(bestCosine: nil, bm25Hits: 0))    // empty corpus signal
        #expect(!RetrievalScoring.isWeak(bestCosine: 0.1, bm25Hits: 2))   // keywords hit → not weak
        #expect(!RetrievalScoring.isWeak(bestCosine: 0.6, bm25Hits: 0))   // semantically close → not weak
        #expect(!RetrievalScoring.isWeak(bestCosine: 0.9, bm25Hits: 5))   // strong both ways
    }
}

@Suite struct CorpusCacheTests {
    private func repo() throws -> (any ChunkRepository, ModelContainer) {
        let container = try ModelContainerFactory.inMemory()
        return (SwiftDataChunkRepository(modelContainer: container), container)
    }

    @Test func decodesOnceAndServesFromCache() async throws {
        let (chunks, _) = try repo()
        try await chunks.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .document, text: "hello",
                                               embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        let cache = CorpusCache(chunks: chunks, dimension: { 3 })
        let first = try await cache.corpus()
        let second = try await cache.corpus()
        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(first[0].vector == [1, 0, 0])
    }

    @Test func countChangeIsDetectedWithoutExplicitInvalidate() async throws {
        let (chunks, _) = try repo()
        let cache = CorpusCache(chunks: chunks, dimension: { 3 })
        #expect(try await cache.corpus().isEmpty)
        try await chunks.insert([ChunkSnapshot(sourceId: UUID(), sourceType: .session, text: "new",
                                               embedding: VectorPacking.pack([0, 1, 0]), chunkIndex: 0)])
        // No invalidate() call — the row-count probe must notice the insert.
        #expect(try await cache.corpus().count == 1)
    }

    @Test func invalidateForcesReload() async throws {
        let (chunks, _) = try repo()
        let source = UUID()
        try await chunks.insert([ChunkSnapshot(sourceId: source, sourceType: .document, text: "v1",
                                               embedding: VectorPacking.pack([1, 0, 0]), chunkIndex: 0)])
        let cache = CorpusCache(chunks: chunks, dimension: { 3 })
        _ = try await cache.corpus()
        // Same-count replacement (reindex): delete + insert — count probe can't see it…
        try await chunks.deleteChunks(sourceId: source)
        try await chunks.insert([ChunkSnapshot(sourceId: source, sourceType: .document, text: "v2",
                                               embedding: VectorPacking.pack([0, 1, 0]), chunkIndex: 0)])
        await cache.invalidate()   // …which is why index writes invalidate explicitly.
        let reloaded = try await cache.corpus()
        #expect(reloaded.first?.text == "v2")
    }
}

@Suite struct RAG2AnswerMappingTests {
    private func packed(_ n: Int) -> [RetrievedChunk] {
        (0..<n).map { i in
            RetrievedChunk(chunk: ChunkSnapshot(sourceId: UUID(), sourceType: .document,
                                                text: "passage \(i + 1)", chunkIndex: i),
                           score: 1)
        }
    }

    @Test func citedSourcesFollowCitationOrderAndDedup() {
        let chunks = packed(4)
        let sources = RAGPipeline.citedSources([3, 1, 3], packed: chunks)
        #expect(sources.count == 2)
        #expect(sources[0].chunkId == chunks[2].chunk.id)   // [3] first, as cited
        #expect(sources[1].chunkId == chunks[0].chunk.id)
    }

    @Test func invalidCitationsAreDroppedAndEmptyFallsBackToAllPacked() {
        let chunks = packed(2)
        #expect(RAGPipeline.citedSources([0, 7], packed: chunks).count == 2)   // all invalid → all packed
        #expect(RAGPipeline.citedSources([], packed: chunks).count == 2)       // none cited → all packed
        #expect(RAGPipeline.citedSources([2, 9], packed: chunks).count == 1)   // 9 dropped, [2] kept
    }

    @Test func rewriteSkippedForStandaloneQuestions() {
        // Standalone questions must NOT pay the rewrite LLM round-trip (voice latency).
        #expect(!RAGPipeline.needsRewrite("what is the refund policy for customers"))
        #expect(!RAGPipeline.needsRewrite("who leads the security team at the company"))
    }

    @Test func rewriteKeptForContextDependentQuestions() {
        #expect(RAGPipeline.needsRewrite("why?"))                        // too short
        #expect(RAGPipeline.needsRewrite("what did they decide about it"))  // pronouns
        #expect(RAGPipeline.needsRewrite("when does that ship to customers"))
        #expect(RAGPipeline.needsRewrite("and his budget approval for the quarter"))
    }

    @Test func assistantTurnsAreTruncatedInMemoryBlock() {
        // Full prior answers echoed into the prompt made small models re-emit them
        // verbatim (field bug). User turns stay complete; assistant turns get a stub.
        let long = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 20)
        let memory = RAGPipeline.memory(from: [
            ChatTurn(role: .user, content: "what is the refund policy?"),
            ChatTurn(role: .assistant, content: long),
        ])
        let assistantLine = memory.split(separator: "\n").last.map(String.init) ?? ""
        #expect(assistantLine.hasSuffix("…"))
        #expect(assistantLine.count < 260)
        #expect(memory.contains("User: what is the refund policy?"))   // user turn untouched
    }

    @Test func nearDuplicateDetectsVerbatimAndAppendedRepeats() {
        let prev = "The shooting took place on Delphi Road, in the Collegeway area of Mississauga, just before 12:30 a.m. Five unmarked cruisers were involved in the investigation and three collided with the Mercedes."
        #expect(RAGPipeline.isNearDuplicate(prev, of: prev))                       // verbatim
        #expect(RAGPipeline.isNearDuplicate(prev + " The stolen car was a Subaru.", of: prev))   // field case: repeat + one line
        #expect(!RAGPipeline.isNearDuplicate("No — digital goods are non-refundable once downloaded.", of: prev))
        #expect(!RAGPipeline.isNearDuplicate("Yes.", of: "Yes."))                  // short answers repeat legitimately
        #expect(!RAGPipeline.isNearDuplicate(prev, of: nil))
    }

    @Test func expansionParsingStripsListMarkers() async {
        let gateway = MockModelGateway(respondReturn: "1. phoenix release date\n- when does phoenix ship")
        let expanded = await RAGPipeline.expandQueries(gateway: gateway, query: "phoenix launch")
        #expect(expanded == ["phoenix release date", "when does phoenix ship"])
    }
}
