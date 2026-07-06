import SwiftUI

/// Red dot + elapsed timer, shown whenever capture is active. Doubles as the
/// consent-visibility indicator (§0.6). Reused by the live screen and Phase 4.
struct RecordingIndicatorView: View {
    let elapsed: TimeInterval
    var isPaused: Bool = false

    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isPaused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .opacity(pulsing ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            Text(Self.formatted(elapsed))
                .font(.body.monospacedDigit())
                .accessibilityLabel("Elapsed \(Int(elapsed)) seconds")
            if isPaused {
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { pulsing = true }
    }

    static func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        RecordingIndicatorView(elapsed: 72)
        RecordingIndicatorView(elapsed: 130, isPaused: true)
    }
}
#endif
