import SwiftUI

/// Ask tab placeholder. Real RAG chat lands in Phase 8.
struct AskView: View {
    var body: some View {
        ContentUnavailableView(
            "Ask Your Knowledge",
            systemImage: "sparkles",
            description: Text("Ask questions across your sessions and documents.")
        )
        .navigationTitle("Ask")
    }
}

#if DEBUG
#Preview { NavigationStack { AskView() } }
#endif
