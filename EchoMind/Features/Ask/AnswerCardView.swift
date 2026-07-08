import SwiftUI

/// Assistant answer card: the answer (or not-found / retrieval-only header),
/// then tappable source snippets (§6.3).
struct AnswerCardView: View {
    let message: AskMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.kind == .notFound {
                Label(message.content, systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Text(message.content)
            }
            if !message.sources.isEmpty {
                Divider()
                Text(message.kind == .retrievalOnly ? "Relevant passages" : "Sources")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(message.sources) { SourceSnippetView(source: $0) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}
