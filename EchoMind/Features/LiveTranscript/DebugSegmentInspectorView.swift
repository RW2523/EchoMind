import SwiftUI

#if DEBUG
/// DEBUG-only overlay proving finalized segments are persisted DURING recording,
/// not just on Stop (§3.1). Polls the store for the active session's segment
/// count and compares it to the in-memory finalized-line count.
struct DebugSegmentInspectorView: View {
    let model: LiveTranscriptViewModel
    let sessions: any SessionRepository

    @State private var persistedCount = 0

    var body: some View {
        HStack {
            Text("DEBUG")
                .font(.caption2.bold())
                .padding(.horizontal, 4)
                .background(.yellow.opacity(0.3))
            Text("in-memory: \(model.finalizedLines.count)")
            Text("persisted: \(persistedCount)")
                .foregroundStyle(persistedCount == model.finalizedLines.count ? .green : .orange)
            Spacer()
        }
        .font(.caption.monospaced())
        .padding(.horizontal)
        .task(id: model.finalizedLines.count) {
            await refresh()
        }
    }

    private func refresh() async {
        guard let id = model.activeSessionId else { persistedCount = 0; return }
        persistedCount = (try? await sessions.fetchSegments(sessionId: id).count) ?? 0
    }
}
#endif
