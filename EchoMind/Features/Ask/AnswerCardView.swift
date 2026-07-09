import SwiftUI

/// Assistant turn, ChatGPT-style: a small brand avatar and full-width text (no
/// bubble), with tappable source snippets underneath (§6.3).
struct AnswerCardView: View {
    let message: AskMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.brandLight)
                .frame(width: 28, height: 28)
                .background(DS.brand.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(DS.brand.opacity(0.3), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 8) {
                if message.kind == .notFound {
                    Label(message.content, systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !message.sources.isEmpty {
                    Text(message.kind == .retrievalOnly ? "Relevant passages" : "Sources")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ForEach(message.sources) { SourceSnippetView(source: $0) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
