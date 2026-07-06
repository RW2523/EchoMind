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
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
