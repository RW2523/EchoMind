import Foundation

nonisolated enum ImportError: LocalizedError, Equatable {
    case accessDenied
    case unreadable(underlying: String)
    case unsupportedType
    case passwordProtectedPDF
    case scannedPDF
    case emptyDocument
    case tooLarge(limitMB: Int)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "EchoMind couldn't access that file."
        case .unreadable:
            return "Couldn't read that file. If it's in iCloud, download it in Files first."
        case .unsupportedType:
            return "That file type isn't supported. Import a .txt, .md, or .pdf."
        case .passwordProtectedPDF:
            return "That PDF is password-protected. Remove the password and try again."
        case .scannedPDF:
            return "This looks like a scanned PDF. Scanned PDFs aren't supported yet."
        case .emptyDocument:
            return "That document has no readable text."
        case .tooLarge(let limitMB):
            return "That document is too large — more than \(limitMB) MB of text."
        }
    }
}
