import Foundation

/// Which embedder the app should use (M2). Built-in NLEmbedding is the always-
/// available default (0 MB, no package); a downloaded EmbeddingGemma upgrades it.
nonisolated enum EmbedderChoice: Equatable, Sendable {
    case builtInNL
    case gemma(modelID: String)

    /// Stable identity written alongside the index. When the resolved choice's
    /// identity differs from the one that built the current index, the index is
    /// stale (its vectors came from a different embedder) and must be rebuilt.
    var identity: String {
        switch self {
        case .builtInNL: return "nl.sentence"
        case .gemma(let id): return "gemma:\(id)"
        }
    }
}

/// Pure decision logic for embedder selection — no I/O, fully unit-testable.
/// Falls back to NLEmbedding whenever the upgrade isn't actually usable, so the
/// app can never end up with no embedder (a dead RAG).
nonisolated struct EmbedderResolver: Sendable {
    func choice(selectedEmbeddingModelID: String?,
                isDownloaded: (String) -> Bool,
                packageLinked: Bool) -> EmbedderChoice {
        guard packageLinked,
              let id = selectedEmbeddingModelID,
              let model = LocalModelCatalog.model(id: id),
              model.kind == .embedding,
              isDownloaded(id)
        else { return .builtInNL }
        return .gemma(modelID: id)
    }

    /// True when the chosen embedder differs from the one that built the index.
    func needsRebuild(choice: EmbedderChoice, activeIdentity: String?) -> Bool {
        guard let activeIdentity else { return false }   // nil = never indexed yet
        return activeIdentity != choice.identity
    }
}
