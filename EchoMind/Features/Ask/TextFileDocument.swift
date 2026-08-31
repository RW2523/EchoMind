import SwiftUI
import UniformTypeIdentifiers

/// Minimal FileDocument wrapping a plain-text payload, so exports can use
/// SwiftUI's `.fileExporter` — the explicit "save/download to Files" dialog
/// (the share sheet's Save to Files is easy to miss).
struct TextFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
