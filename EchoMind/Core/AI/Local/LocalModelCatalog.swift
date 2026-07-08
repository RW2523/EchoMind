import Foundation

/// What a downloadable model does — chat/generation vs text embedding. Lets one
/// catalog + one Model Manager + one downloader serve both the LLM (Phase 14) and
/// the EmbeddingGemma retrieval embedder (M2) with no parallel plumbing.
nonisolated enum ModelKind: String, Sendable, Equatable {
    case chat
    case embedding
    case tts
}

/// Metadata for a downloadable on-device model (V2 §B3). The catalog is data, not
/// code paths — new/better small models drop in by adding a row, no app update to
/// the engine. Weights come from the pinned Hugging Face repo (mlx-community),
/// fetched on explicit user consent (Phase 15).
nonisolated struct LocalModel: Identifiable, Sendable, Equatable {
    let id: String
    let kind: ModelKind
    let displayName: String
    /// Hugging Face repo id, e.g. "mlx-community/Qwen2.5-1.5B-Instruct-4bit".
    let huggingFaceRepo: String
    let approxDownloadMB: Int
    /// Chat: context window in tokens. Embedding: output vector dimension.
    let contextSize: Int
    let parameterHint: String        // "1.5B · 4-bit" for the UI
    let isDefault: Bool

    var approxDownloadDescription: String {
        approxDownloadMB >= 1024
            ? String(format: "%.1f GB", Double(approxDownloadMB) / 1024)
            : "\(approxDownloadMB) MB"
    }
}

nonisolated enum LocalModelCatalog {
    /// Curated, quantized, Metal-friendly models that fit the phone budget.
    /// NOTE: HF repo ids on mlx-community drift over time — verify each still
    /// resolves before shipping a new row (it's data, so a fix is a one-line edit).
    static let all: [LocalModel] = [
        // MARK: Chat / generation
        LocalModel(
            id: "qwen2.5-1.5b-instruct-4bit",
            kind: .chat,
            displayName: "Qwen2.5 1.5B Instruct",
            huggingFaceRepo: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            approxDownloadMB: 900,
            contextSize: 8_192,
            parameterHint: "1.5B · 4-bit",
            isDefault: true),
        LocalModel(
            id: "llama-3.2-1b-instruct-4bit",
            kind: .chat,
            displayName: "Llama 3.2 1B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            approxDownloadMB: 700,
            contextSize: 8_192,
            parameterHint: "1B · 4-bit",
            isDefault: false),
        LocalModel(
            id: "qwen2.5-3b-instruct-4bit",
            kind: .chat,
            displayName: "Qwen2.5 3B Instruct",
            huggingFaceRepo: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            approxDownloadMB: 1_800,
            contextSize: 8_192,
            parameterHint: "3B · 4-bit — newer iPhones",
            isDefault: false),

        // MARK: Embedding (M2 — retrieval brain, upgrades NLEmbedding)
        LocalModel(
            id: "embeddinggemma-300m",
            kind: .embedding,
            displayName: "EmbeddingGemma 300M",
            huggingFaceRepo: "mlx-community/embeddinggemma-300m",
            approxDownloadMB: 200,
            contextSize: 768,           // output vector dimension
            parameterHint: "300M · retrieval embeddings",
            isDefault: false),

        // MARK: Text-to-speech (V4 — Kokoro; upgrades AVSpeechSynthesizer)
        LocalModel(
            id: "kokoro-82m",
            kind: .tts,
            displayName: "Kokoro 82M",
            huggingFaceRepo: "mlx-community/Kokoro-82M-4bit",
            approxDownloadMB: 90,
            contextSize: 0,             // n/a for TTS
            parameterHint: "82M · warm “af_heart” voice",
            isDefault: false),
    ]

    static let chatModels: [LocalModel] = all.filter { $0.kind == .chat }
    static let embeddingModels: [LocalModel] = all.filter { $0.kind == .embedding }
    static let voiceModels: [LocalModel] = all.filter { $0.kind == .tts }

    /// Default chat model (the LLM engine's fallback selection).
    static let `default`: LocalModel = chatModels.first(where: \.isDefault) ?? chatModels[0]

    static func model(id: String) -> LocalModel? { all.first { $0.id == id } }
}
