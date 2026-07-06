import SwiftUI

/// One knowledge source: type icon, title, date, size/duration, status badge.
struct KnowledgeSourceRow: View {
    let source: KnowledgeSource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(source.date, format: .dateTime.month().day().year())
                    if let detail { Text("·"); Text(detail) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let badge { badgeView(badge) }
        }
    }

    private var icon: String {
        switch source {
        case .document(let doc): return doc.fileType == .pdf ? "doc.richtext" : "doc.text"
        case .session: return "waveform"
        }
    }

    private var detail: String? {
        switch source {
        case .document(let doc):
            let bytes = doc.textContent.utf8.count
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        case .session(let session):
            return SessionExporter.durationText(session.duration)
        }
    }

    private var badge: String? {
        if case .document(let doc) = source, doc.status == .imported { return "Not indexed yet" }
        if case .document(let doc) = source, doc.status == .indexing { return "Indexing…" }
        return nil
    }

    @ViewBuilder private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
