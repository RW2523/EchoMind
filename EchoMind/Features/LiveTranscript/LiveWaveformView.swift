import SwiftUI
import Combine

/// Real-time scrolling waveform driven by the audio level stream (V2 §D2).
/// Keeps a rolling buffer of recent levels and mirrors them around the centre
/// line for a classic voice-memo look; freezes when capture is paused/stopped.
struct LiveWaveformView: View {
    var level: Float
    var isActive: Bool
    var barCount: Int = 56

    @State private var samples: [Float]
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(level: Float, isActive: Bool, barCount: Int = 56) {
        self.level = level
        self.isActive = isActive
        self.barCount = barCount
        _samples = State(initialValue: Array(repeating: 0, count: barCount))
    }

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(samples.count)
            let barWidth = slot * 0.55
            let midY = size.height / 2
            for (index, sample) in samples.enumerated() {
                let amplitude = max(0.02, CGFloat(sample))
                let barHeight = amplitude * size.height
                let x = CGFloat(index) * slot + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [DS.brand, DS.brandDeep]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)))
            }
        }
        .drawingGroup()
        .onReceive(timer) { _ in
            guard isActive else { return }
            samples.removeFirst()
            samples.append(level)
        }
        .onChange(of: isActive) { _, active in
            if !active { samples = Array(repeating: 0, count: barCount) }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    LiveWaveformView(level: 0.6, isActive: true)
        .frame(height: 90)
        .padding()
}
#endif
