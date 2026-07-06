import SwiftUI

/// Loads a `SessionSnapshot` by id, then shows `SessionDetailView` — used as the
/// `.session` tap-through target from Ask sources.
struct SessionLoaderView: View {
    let sessionId: UUID
    var timestamp: TimeInterval?

    @Environment(AppDependencies.self) private var dependencies
    @State private var snapshot: SessionSnapshot?

    var body: some View {
        Group {
            if let snapshot {
                SessionDetailView(session: snapshot)
            } else {
                ProgressView()
            }
        }
        .task {
            snapshot = try? await dependencies.sessionRepository.fetchSession(id: sessionId)
        }
    }
}
