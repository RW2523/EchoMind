import Testing
import Foundation
@testable import EchoMind

@Suite struct DocumentImportServiceTests {
    private func tempFile(name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    private func service() throws -> (DefaultDocumentImportService, any DocumentRepository) {
        let container = try ModelContainerFactory.inMemory()
        let repo = SwiftDataDocumentRepository(modelContainer: container)
        return (DefaultDocumentImportService(documents: repo), repo)
    }

    @Test func importsPlainTextFile() async throws {
        let (svc, repo) = try service()
        let url = try tempFile(name: "notes.txt", contents: Data("Hello world.\nSecond line.".utf8))
        let id = try await svc.importDocument(at: url)
        let doc = try await repo.fetchDocument(id: id)
        #expect(doc?.title == "notes")
        #expect(doc?.fileType == .txt)
        #expect(doc?.status == .imported)
        #expect(doc?.textContent.contains("Hello world.") == true)
    }

    @Test func markdownFileGetsMdType() async throws {
        let (svc, repo) = try service()
        let url = try tempFile(name: "readme.md", contents: Data("# Title\n\nBody.".utf8))
        let id = try await svc.importDocument(at: url)
        #expect(try await repo.fetchDocument(id: id)?.fileType == .md)
    }

    @Test func emptyFileThrows() async throws {
        let (svc, _) = try service()
        let url = try tempFile(name: "empty.txt", contents: Data("   \n  ".utf8))
        await #expect(throws: ImportError.emptyDocument) {
            _ = try await svc.importDocument(at: url)
        }
    }

    @Test func unsupportedTypeThrows() async throws {
        let (svc, _) = try service()
        let url = try tempFile(name: "data.json", contents: Data("{}".utf8))
        await #expect(throws: ImportError.unsupportedType) {
            _ = try await svc.importDocument(at: url)
        }
    }

    @Test func nonUTF8TextStillDecodes() async throws {
        let (svc, repo) = try service()
        // 0x92 is a CP1252 curly apostrophe, invalid UTF-8 — must not hard-fail.
        var bytes = Data("It".utf8); bytes.append(0x92); bytes.append(contentsOf: Data("s fine".utf8))
        let url = try tempFile(name: "legacy.txt", contents: bytes)
        let id = try await svc.importDocument(at: url)
        #expect(try await repo.fetchDocument(id: id)?.textContent.isEmpty == false)
    }
}
