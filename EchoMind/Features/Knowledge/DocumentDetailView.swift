import SwiftUI

/// Document reader — per-page rendering of `Document.textContent`, scrolled to a
/// citation's page (§6.3). The `.document` tap-through target from Ask.
struct DocumentDetailView: View {
    let documentId: UUID
    var initialPageNumber: Int?

    @Environment(AppDependencies.self) private var dependencies
    @State private var pages: [String] = []
    @State private var title = ""

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, text in
                    Section("Page \(index + 1)") {
                        Text(text)
                    }
                    .id(index + 1)
                }
            }
            .task {
                await load()
                if let page = initialPageNumber, page >= 1, page <= pages.count {
                    withAnimation { proxy.scrollTo(page, anchor: .top) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        guard let document = try? await dependencies.documentRepository.fetchDocument(id: documentId) else { return }
        title = document.title
        pages = Self.split(document.textContent, pageBreaks: document.pageBreaks)
    }

    static func split(_ text: String, pageBreaks: [Int]) -> [String] {
        guard !pageBreaks.isEmpty else { return text.isEmpty ? [] : [text] }
        let utf16 = Array(text.utf16)
        var pages: [String] = []
        for (index, start) in pageBreaks.enumerated() {
            let end = index + 1 < pageBreaks.count ? pageBreaks[index + 1] : utf16.count
            let lower = min(max(0, start), utf16.count)
            let upper = min(max(lower, end), utf16.count)
            let slice = Array(utf16[lower..<upper])
            pages.append(String(decoding: slice, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return pages
    }
}
