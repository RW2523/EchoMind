import Foundation

/// Which TTS voice to use (Voice Agent V4). AVSpeechSynthesizer is the always-
/// available floor; a downloaded Kokoro voice upgrades it. Pure decision logic,
/// mirroring `EmbedderResolver` — the app can never end up without a voice.
nonisolated enum VoiceChoice: Equatable, Sendable {
    case systemAV
    case kokoro(modelID: String)

    var identity: String {
        switch self {
        case .systemAV: return "av.system"
        case .kokoro(let id): return "kokoro:\(id)"
        }
    }
}

nonisolated struct SpeechSynthesizerResolver: Sendable {
    func choice(selectedVoiceModelID: String?,
                isDownloaded: (String) -> Bool,
                packageLinked: Bool) -> VoiceChoice {
        guard packageLinked,
              let id = selectedVoiceModelID,
              let model = LocalModelCatalog.model(id: id),
              model.kind == .tts,
              isDownloaded(id)
        else { return .systemAV }
        return .kokoro(modelID: id)
    }
}
