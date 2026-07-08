import Foundation

/// Metadata for a downloadable on-device model (V2 §B3). The catalog is data, not
/// code paths — new/better small models drop in by adding a row, no app update to
/// the engine. Weights come from the pinned Hugging Face repo (mlx-community),
/// fetched on explicit user consent (Phase 15).
nonisolated struct LocalModel: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    /// Hugging Face repo id, e.g. "mlx-community/Qwen2.5-1.5B-Instruct-4bit".
    let huggingFaceRepo: String
    let approxDownloadMB: Int
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
    static let all: [LocalModel] = [
        LocalModel(
            id: "qwen2.5-1.5b-instruct-4bit",
            displayName: "Qwen2.5 1.5B Instruct",
            huggingFaceRepo: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            approxDownloadMB: 900,
            contextSize: 8_192,
            parameterHint: "1.5B · 4-bit",
            isDefault: true),
        LocalModel(
            id: "llama-3.2-1b-instruct-4bit",
            displayName: "Llama 3.2 1B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            approxDownloadMB: 700,
            contextSize: 8_192,
            parameterHint: "1B · 4-bit",
            isDefault: false),
        LocalModel(
            id: "qwen2.5-3b-instruct-4bit",
            displayName: "Qwen2.5 3B Instruct",
            huggingFaceRepo: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            approxDownloadMB: 1_800,
            contextSize: 8_192,
            parameterHint: "3B · 4-bit — newer iPhones",
            isDefault: false),
    ]

    static let `default`: LocalModel = all.first(where: \.isDefault) ?? all[0]

    static func model(id: String) -> LocalModel? { all.first { $0.id == id } }
}
