import SwiftUI

/// EchoMind design system. One source of truth for color, spacing, radius, motion,
/// and reusable surfaces so every screen looks intentional, cohesive, and alive.
enum DS {
    // Brand palette — a confident blue with violet/cyan accents for a rich aurora.
    static let brand = Color(red: 0.04, green: 0.40, blue: 0.90)
    static let brandDeep = Color(red: 0.02, green: 0.24, blue: 0.70)
    static let violet = Color(red: 0.42, green: 0.24, blue: 0.88)
    static let cyan = Color(red: 0.10, green: 0.64, blue: 0.94)

    static let brandGradient = LinearGradient(
        colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let vividGradient = LinearGradient(
        colors: [cyan, brand, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Spacing scale.
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
    static let lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32

    // Corner radii.
    static let rSm: CGFloat = 12, rMd: CGFloat = 18, rLg: CGFloat = 26, rXl: CGFloat = 34

    // Signature motion.
    static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.7)
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.85)
}

// MARK: - Aurora background

/// A living, breathing brand backdrop: an animated mesh gradient that drifts
/// slowly under the whole app. Frosted `.material` cards sit beautifully on top.
/// Honors Reduce Motion (falls back to a still mesh) and an optional `intensity`
/// (e.g. audio level) that blooms the colors.
struct BrandBackground: View {
    var intensity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation) { timeline in
                    mesh(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .animation(DS.smooth, value: intensity)
    }

    private func mesh(at t: TimeInterval) -> some View {
        let bloom = 0.5 + intensity * 0.4
        return MeshGradient(width: 3, height: 3,
                            points: Self.points(t),
                            colors: Self.colors)
            .opacity(bloom)
            .blur(radius: 2)
    }

    /// 3×3 control grid — corners pinned, interior/edge points drift on sines.
    static func points(_ t: TimeInterval) -> [SIMD2<Float>] {
        func w(_ speed: Double, _ amp: Double, _ phase: Double) -> Float {
            Float(sin(t * speed + phase) * amp)
        }
        return [
            .init(0, 0), .init(0.5 + w(0.23, 0.10, 0), 0), .init(1, 0),
            .init(0, 0.5 + w(0.19, 0.10, 1)),
            .init(0.5 + w(0.21, 0.10, 2), 0.5 + w(0.17, 0.10, 3)),
            .init(1, 0.5 + w(0.20, 0.10, 4)),
            .init(0, 1), .init(0.5 + w(0.22, 0.10, 5), 1), .init(1, 1),
        ]
    }

    static let colors: [Color] = [
        DS.cyan,        DS.brand,       DS.violet,
        DS.brand,       DS.brandDeep,   DS.brand,
        DS.violet,      DS.brand,       DS.cyan,
    ]
}

// MARK: - Surfaces

/// A soft, elevated frosted surface with a subtle top-light and layered shadow.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = DS.lg
    var radius: CGFloat = DS.rMd
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.02)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8))
            .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
    }
}

// MARK: - Hero icon badge (animated)

/// A gradient circle badge for hero icons, with a soft glow and an optional
/// slow breathing pulse.
struct BrandIconBadge: View {
    let systemName: String
    var size: CGFloat = 112
    var pulse: Bool = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.vividGradient)
                .frame(width: size, height: size)
                .shadow(color: DS.brand.opacity(0.5), radius: 22, y: 12)
                .scaleEffect(breathe ? 1.04 : 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: DS.brandDeep.opacity(0.4), radius: 4, y: 2)
        }
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - Button styles

/// Prominent, brand-gradient primary action with a springy press + glow.
struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DS.vividGradient, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .shadow(color: DS.brand.opacity(configuration.isPressed ? 0.2 : 0.4),
                    radius: configuration.isPressed ? 8 : 16, y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.bouncy, value: configuration.isPressed)
    }
}

/// Tappable card/press feedback: a gentle spring scale, for NavigationLinks etc.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(DS.bouncy, value: configuration.isPressed)
    }
}

// MARK: - Effects

private struct Glow: ViewModifier {
    var color: Color
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.55), radius: radius)
            .shadow(color: color.opacity(0.3), radius: radius * 2)
    }
}

/// A rotating conic-gradient ring — a premium accent around hero elements.
struct AnimatedRing: View {
    var lineWidth: CGFloat = 3
    @State private var angle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(colors: [DS.cyan, DS.brand, DS.violet, DS.cyan],
                                center: .center, angle: .degrees(angle)),
                lineWidth: lineWidth)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { angle = 360 }
            }
    }
}

/// Sweeping shimmer for skeletons / loading placeholders.
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                    .blendMode(.overlay)
            }
            .allowsHitTesting(false)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

/// Staggered entrance: fade + rise + spring, delayed for a cascade effect.
private struct RevealOnAppear: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(DS.smooth.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// EchoMind look, applied once at the root: rounded typeface + brand tint.
    func echoMindStyle() -> some View { fontDesign(.rounded).tint(DS.brand) }

    func glow(_ color: Color = DS.brand, radius: CGFloat = 10) -> some View {
        modifier(Glow(color: color, radius: radius))
    }
    func shimmering() -> some View { modifier(Shimmer()) }
    func revealOnAppear(delay: Double = 0) -> some View { modifier(RevealOnAppear(delay: delay)) }

    /// Gradient-filled text/shape using the brand vivid gradient.
    func vividForeground() -> some View { foregroundStyle(DS.vividGradient) }
}
