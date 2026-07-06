import Foundation

/// Document persistence. `delete` sweeps the document's knowledge chunks in the
/// same transaction (chunks are polymorphic, no DB cascade — §2.2).
nonisolated protocol DocumentRepository: Sendable {
    func create(_ snapshot: DocumentSnapshot) async throws
    func fetchAll() async throws -> [DocumentSnapshot]
    func fetchDocument(id: UUID) async throws -> DocumentSnapshot?
    func updateStatus(id: UUID, status: DocumentStatus) async throws
    func delete(id: UUID) async throws
}
