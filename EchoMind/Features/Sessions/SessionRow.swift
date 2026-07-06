import SwiftUI

/// Title, date, duration, and a lazily-loaded 2-line transcript preview (§4.2).
struct SessionRow: View {
    let session: SessionSnapshot
    let repository: any SessionRepository

    @State private var preview = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.headline)
            HStack(spacing: 6) {
                Text(session.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text(SessionExporter.durationText(session.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .task(id: session.id) {
            preview = (try? await repository.previewText(sessionID: session.id, maxCharacters: 160)) ?? ""
        }
    }
}
