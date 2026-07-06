import SwiftUI

/// Knowledge tab placeholder. Real sources list + import land in Phase 6.
struct KnowledgeView: View {
    var body: some View {
        ContentUnavailableView(
            "No Knowledge Yet",
            systemImage: "books.vertical",
            description: Text("Imported documents and saved transcripts will appear here.")
        )
        .navigationTitle("Knowledge")
    }
}

#if DEBUG
#Preview { NavigationStack { KnowledgeView() } }
#endif
