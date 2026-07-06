import SwiftUI

/// Sessions tab placeholder. Real list + search + detail land in Phase 4.
struct SessionsView: View {
    var body: some View {
        ContentUnavailableView(
            "No Sessions Yet",
            systemImage: "waveform",
            description: Text("Recorded sessions will appear here.")
        )
        .navigationTitle("Sessions")
    }
}

#if DEBUG
#Preview { NavigationStack { SessionsView() } }
#endif
