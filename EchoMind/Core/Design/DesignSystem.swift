import SwiftUI

/// EchoMind design system (V2 §D0). One source of truth for color, spacing,
/// radius, and reusable surfaces so every screen looks intentional and cohesive.
enum DS {
    // Brand — a confident blue, echoing the waveform mark.
    static let brand = Color(red: 0.04, green: 0.40, blue: 0.90)
    static let brandDeep = Color(red: 0.02, green: 0.26, blue: 0.72)
    static let brandGradient = LinearGradient(
        colors: [brand, brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Spacing scale.
    static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
    static let lg: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32

    // Corner radii.
    static let rSm: CGFloat = 12, rMd: CGFloat = 18, rLg: CGFloat = 26
}

/// Ambient brand backdrop for hero screens — soft radial brand glows over the
/// system background, reacting to an optional intensity (e.g. audio level).
struct BrandBackground: View {
    var intensity: Double = 0

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(colors: [DS.brand.opacity(0.28 + intensity * 0.25), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 420)
            RadialGradient(colors: [DS.brandDeep.opacity(0.20 + intensity * 0.2), .clear],
                           center: .bottomTrailing, startRadius: 20, endRadius: 480)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: intensity)
    }
}

/// A soft, elevated surface. Uses regular material so it sits well on the
/// brand backdrop and adapts to light/dark automatically.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = DS.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }
}

extension View {
    /// EchoMind look, applied once at the root: rounded typeface + brand tint.
    func echoMindStyle() -> some View {
        self.fontDesign(.rounded).tint(DS.brand)
    }
}

/// A gradient circle badge for hero icons.
struct BrandIconBadge: View {
    let systemName: String
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle()
                .fill(DS.brandGradient)
                .frame(width: size, height: size)
                .shadow(color: DS.brand.opacity(0.4), radius: 18, y: 10)
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Prominent, brand-gradient primary action.
struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(DS.brandGradient, in: RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .shadow(color: DS.brand.opacity(0.35), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}
