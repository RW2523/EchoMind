import Foundation

/// Unified knowledge-source list item: imported documents AND session
/// transcripts (§4.3). Snapshot payloads keep Models/ free of SwiftData.
nonisolated enum KnowledgeSource: Identifiable, Equatable {
    case document(DocumentSnapshot)
    case session(SessionSnapshot)

    var id: UUID {
        switch self {
        case .document(let doc): return doc.id
        case .session(let session): return session.id
        }
    }

    var title: String {
        switch self {
        case .document(let doc): return doc.title
        case .session(let session): return session.title
        }
    }

    var date: Date {
        switch self {
        case .document(let doc): return doc.createdAt
        case .session(let session): return session.createdAt
        }
    }
}
