import Testing
@testable import EchoMind

@Suite struct EmbedderResolverTests {
    let resolver = EmbedderResolver()
    let gemmaID = "embeddinggemma-300m"      // an embedding-kind catalog id
    let chatID = "qwen2.5-1.5b-instruct-4bit" // a chat-kind catalog id

    @Test func fallsBackToBuiltInWhenPackageNotLinked() {
        let c = resolver.choice(selectedEmbeddingModelID: gemmaID,
                                isDownloaded: { _ in true }, packageLinked: false)
        #expect(c == .builtInNL)
    }

    @Test func fallsBackWhenNothingSelected() {
        let c = resolver.choice(selectedEmbeddingModelID: nil,
                                isDownloaded: { _ in true }, packageLinked: true)
        #expect(c == .builtInNL)
    }

    @Test func fallsBackWhenSelectedNotDownloaded() {
        let c = resolver.choice(selectedEmbeddingModelID: gemmaID,
                                isDownloaded: { _ in false }, packageLinked: true)
        #expect(c == .builtInNL)
    }

    @Test func rejectsChatModelAsEmbedder() {
        let c = resolver.choice(selectedEmbeddingModelID: chatID,
                                isDownloaded: { _ in true }, packageLinked: true)
        #expect(c == .builtInNL)   // kind guard: a chat model can't be the embedder
    }

    @Test func resolvesGemmaWhenAllConditionsMet() {
        let c = resolver.choice(selectedEmbeddingModelID: gemmaID,
                                isDownloaded: { $0 == self.gemmaID }, packageLinked: true)
        #expect(c == .gemma(modelID: gemmaID))
    }

    @Test func identityStringsAreStableAndDistinct() {
        #expect(EmbedderChoice.builtInNL.identity == "nl.sentence")
        #expect(EmbedderChoice.gemma(modelID: gemmaID).identity == "gemma:\(gemmaID)")
    }

    @Test func needsRebuildOnlyWhenIdentityDiffers() {
        let gemma = EmbedderChoice.gemma(modelID: gemmaID)
        #expect(resolver.needsRebuild(choice: gemma, activeIdentity: nil) == false)          // never indexed
        #expect(resolver.needsRebuild(choice: gemma, activeIdentity: "nl.sentence") == true)  // switched
        #expect(resolver.needsRebuild(choice: gemma, activeIdentity: gemma.identity) == false)
    }
}

@Suite struct LocalModelCatalogKindTests {
    @Test func catalogSplitsByKind() {
        #expect(LocalModelCatalog.chatModels.allSatisfy { $0.kind == .chat })
        #expect(LocalModelCatalog.embeddingModels.allSatisfy { $0.kind == .embedding })
        #expect(!LocalModelCatalog.embeddingModels.isEmpty)
    }

    @Test func defaultIsAChatModel() {
        #expect(LocalModelCatalog.default.kind == .chat)
    }
}
