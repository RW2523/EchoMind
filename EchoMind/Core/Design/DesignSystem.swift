import SwiftUI

/// EchoMind design system — a deep-navy dark theme with a single electric-blue
/// accent (no rainbow gradients), subtle grid + glow, and dark glass panels. One
/// source of truth for color, spacing, radius, motion, and reusable surfaces.
enum DS {
    // Surfaces (dark navy, matching the brand look).
    static let bg = Color(red: 0.027, green: 0.043, blue: 0.11)        // deep navy backdrop
    static let bgElevated = Color(red: 0.06, green: 0.09, blue: 0.20)  // card/panel
    static let stroke = Color(red: 0.29, green: 0.55, blue: 1.0)       // faint blue edges

    // Brand — one confident electric blue, with a lighter tint for text.
    static let brand = Color(red: 0.29, green: 0.55, blue: 1.0)        // #4A8CFF
    static let brandDeep = Color(red: 0.13, green: 0.33, blue: 0.86)
    static let brandLight = Color(red: 0.58, green: 0.78, blue: 1.0)

    static let brandGradient = LinearGradient(
        colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Kept for source compatibility — now a tasteful blue (no cyan/violet).
    static let vividGradient = LinearGradient(
        colors: [brandLight, brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let titleGradient = LinearGradient(
        colors: [brandLight, brand], startPoint: .leading, endPoint: .trailing)

    // Spacing scale.
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
    static let lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32

    // Corner radii.
    static let rSm: CGFloat = 12, rMd: CGFloat = 18, rLg: CGFloat = 26, rXl: CGFloat = 34

    // Signature motion.
    static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.7)
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.85)
}

// MARK: - Background

/// The signature backdrop: a deep-navy field with a faint tech grid and soft blue
/// glows — calm and premium, not busy. `intensity` (e.g. audio level) brightens
/// the glow. Honors Reduce Motion for the animation only.
struct BrandBackground: View {
    var intensity: Double = 0

    var body: some View {
        ZStack {
            DS.bg
            GridOverlay().opacity(0.45)
            RadialGradient(colors: [DS.brand.opacity(0.22 + intensity * 0.22), .clear],
                           center: .top, startRadius: 8, endRadius: 520)
            RadialGradient(colors: [DS.brandDeep.opacity(0.18), .clear],
                           center: .bottomTrailing, startRadius: 8, endRadius: 460)
        }
        .ignoresSafeArea()
        .animation(DS.smooth, value: intensity)
    }
}

/// A faint blueprint grid, drawn once.
private struct GridOverlay: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 46
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(path, with: .color(DS.brand.opacity(0.06)), lineWidth: 0.5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Surfaces

/// A dark glass panel with a faint glowing blue edge — the reference card look.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = DS.lg
    var radius: CGFloat = DS.rMd
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(DS.bgElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [DS.stroke.opacity(0.35), DS.stroke.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

// MARK: - Hero icon badge

/// A rounded-square badge with a glowing blue icon on dark navy — matches the
/// reference feature icons. Optional slow breathing pulse.
struct BrandIconBadge: View {
    let systemName: String
    var size: CGFloat = 112
    var pulse: Bool = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(DS.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(DS.brand.opacity(0.4), lineWidth: 1))
                .frame(width: size, height: size)
                .shadow(color: DS.brand.opacity(0.5), radius: 24, y: 0)
                .scaleEffect(breathe ? 1.04 : 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(DS.brandLight)
                .shadow(color: DS.brand.opacity(0.8), radius: 10)
        }
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

// MARK: - Button styles

/// Prominent, blue primary action with a springy press + glow.
struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .shadow(color: DS.brand.opacity(configuration.isPressed ? 0.25 : 0.5),
                    radius: configuration.isPressed ? 8 : 18, y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(DS.bouncy, value: configuration.isPressed)
    }
}

/// Tappable card/press feedback: a gentle spring scale.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
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

/// A rotating blue glow ring — a premium accent around hero elements.
struct AnimatedRing: View {
    var lineWidth: CGFloat = 3
    @State private var angle = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(colors: [DS.brandDeep, DS.brand, DS.brandLight, DS.brandDeep],
                                center: .center, angle: .degrees(angle)),
                lineWidth: lineWidth)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { angle = 360 }
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
    /// EchoMind look, applied once at the root: rounded typeface + brand tint + dark.
    func echoMindStyle() -> some View {
        fontDesign(.rounded).tint(DS.brand).preferredColorScheme(.dark)
    }

    func glow(_ color: Color = DS.brand, radius: CGFloat = 10) -> some View {
        modifier(Glow(color: color, radius: radius))
    }
    func revealOnAppear(delay: Double = 0) -> some View { modifier(RevealOnAppear(delay: delay)) }

    /// Gradient-filled text using the brand title gradient.
    func vividForeground() -> some View { foregroundStyle(DS.titleGradient) }
}
