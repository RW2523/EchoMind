import SwiftUI

/// One source citation: title, page/timestamp, preview — tap opens the document
/// at its page or the session at its segment (§6.3).
struct SourceSnippetView: View {
    let source: AskSource

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: source.sourceType == .document ? "doc.text" : "waveform")
                        .font(.caption)
                    Text(source.title).font(.subheadline.bold()).lineLimit(1)
                    if let detail = source.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let preview = source.preview {
                    Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var destination: some View {
        switch source.sourceType {
        case .document:
            DocumentDetailView(documentId: source.sourceId, initialPageNumber: source.pageNumber)
        case .session:
            SessionLoaderView(sessionId: source.sourceId, timestamp: source.timestamp)
        }
    }
}
