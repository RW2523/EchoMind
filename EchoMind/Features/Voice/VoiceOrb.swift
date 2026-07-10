import SwiftUI

/// The animated centerpiece of the voice conversation (ChatGPT/Grok-style). A soft
/// glowing orb whose motion reads the agent's state: a calm breath when idle, a
/// responsive shimmer while listening, a slow swirl while thinking, and full
/// radiating pulses while speaking. Purely decorative and self-driving via
/// `TimelineView`; freezes to a static glow under Reduce Motion.
struct VoiceOrb: View {
    enum Mode: Equatable { case idle, listening, thinking, speaking, error }

    let mode: Mode
    /// 0…1 live signal (e.g. transcript growth or speech energy) that swells the orb.
    var level: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intensity: Double {
        switch mode {
        case .idle: return 0.18
        case .listening: return 0.45 + level * 0.4
        case .thinking: return 0.5
        case .speaking: return 0.8
        case .error: return 0.1
        }
    }

    private var tint: Color {
        switch mode {
        case .error: return Color(red: 0.95, green: 0.45, blue: 0.45)
        case .thinking: return DS.brandLight
        default: return DS.brand
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, t: t)
            }
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.5), value: mode)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let half = min(size.width, size.height) / 2
        // Base sized so every layer (halo, lobes, rings) fades to clear BEFORE the
        // Canvas edge — otherwise the clipped glow shows as a square.
        let base = half * 0.44
        let breathe = 1 + sin(t * 1.1) * 0.03 * (1 + intensity)
        let swirl = mode == .thinking ? t * 0.9 : t * 0.25

        // Outer glow — a soft radial halo that swells with intensity but always fades
        // to transparent inside the frame (endRadius ≤ half).
        let haloR = half * (0.80 + intensity * 0.18)
        context.fill(
            Circle().path(in: CGRect(x: center.x - haloR, y: center.y - haloR,
                                     width: haloR * 2, height: haloR * 2)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(0.28 + intensity * 0.25), .clear]),
                center: center, startRadius: 0, endRadius: haloR))

        // Three offset translucent lobes that orbit slightly → an organic, living blob.
        let lobeCount = 3
        for i in 0..<lobeCount {
            let phase = swirl + Double(i) * (2 * .pi / Double(lobeCount))
            let wobble = 0.10 + 0.06 * sin(t * 1.7 + Double(i))
            let offset = base * (0.10 + intensity * 0.22)
            let lc = CGPoint(x: center.x + cos(phase) * offset,
                             y: center.y + sin(phase) * offset)
            let r = base * (0.9 + wobble) * breathe
            let colors = [DS.brandLight, DS.brand, DS.brandDeep]
            context.fill(
                Circle().path(in: CGRect(x: lc.x - r, y: lc.y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(
                    Gradient(colors: [colors[i].opacity(0.55), colors[i].opacity(0.0)]),
                    center: lc, startRadius: 0, endRadius: r))
        }

        // Bright core.
        let coreR = base * (0.62 + intensity * 0.10) * breathe
        context.fill(
            Circle().path(in: CGRect(x: center.x - coreR, y: center.y - coreR,
                                     width: coreR * 2, height: coreR * 2)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.9), tint.opacity(0.85), tint.opacity(0.2)]),
                center: CGPoint(x: center.x - coreR * 0.25, y: center.y - coreR * 0.3),
                startRadius: 0, endRadius: coreR * 1.1))

        // Speaking: concentric rings radiating outward on a loop (kept inside frame).
        if mode == .speaking {
            for i in 0..<3 {
                let progress = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let r = min(base * 0.9 + progress * (half - base * 0.9), half - 1)
                let alpha = (1 - progress) * 0.35
                context.stroke(
                    Circle().path(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                    with: .color(tint.opacity(alpha)), lineWidth: 2)
            }
        }
    }
}
