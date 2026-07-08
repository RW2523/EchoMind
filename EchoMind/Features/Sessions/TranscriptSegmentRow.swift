import SwiftUI

/// One transcript line: `[HH:MM:SS]` timestamp above the segment text (§4.2).
struct TranscriptSegmentRow: View {
    let segment: SegmentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let speaker = segment.speakerLabel, !speaker.isEmpty {
                    Text(speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.brand)
                }
                Text("[\(SessionExporter.timestamp(segment.startTime))]")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(segment.text)
        }
        .padding(.vertical, 2)
    }
}
