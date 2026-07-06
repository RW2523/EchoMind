import SwiftUI

/// Summary slot (§4.1 contract 3). Placeholder in Phase 4 — Phase 5 replaces
/// this view's body with the structured MeetingSummary + Generate button.
struct SummarySection: View {
    let session: SessionSnapshot

    var body: some View {
        Section("Summary") {
            if session.summaryJSON == nil {
                Text("No summary yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Summary available.")
            }
        }
    }
}
