import Foundation
import SwiftData

/// The frozen V1 schema (spec §8). All six models are declared now — even the
/// ones with no UI until Phases 7–8 — so we never run a mid-project SwiftData
/// migration. Later changes must be additive and reviewed against spec §8.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Session.self,
            TranscriptSegment.self,
            Document.self,
            KnowledgeChunk.self,
            ChatMessage.self,
            AppSettings.self,
            MemoryFact.self,
        ]
    }
}
