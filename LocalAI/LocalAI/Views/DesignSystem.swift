import SwiftUI

// MARK: - Color Palette

extension Color {
    static let bg         = Color(hex: "08080E")
    static let surface    = Color(hex: "0F0F1B")
    static let surfaceHi  = Color(hex: "161625")
    static let border     = Color.white.opacity(0.06)
    static let borderHi   = Color.white.opacity(0.09)
    static let txt1       = Color.white
    static let txt2       = Color.white.opacity(0.40)
    static let txt3       = Color.white.opacity(0.18)

    // One calm accent — soft indigo. All "violet/pink/cyan" map here.
    static let violet     = Color(hex: "7B7EF8")
    static let pink       = Color(hex: "9D8DF5")   // was hot pink → soft lavender
    static let cyan       = Color(hex: "7B7EF8")   // collapsed into accent
    static let orange     = Color(hex: "D4884A")   // warm, desaturated
}

// MARK: - Model accent helpers

extension AIModel {
    var color1: Color { accentColor }
    var color2: Color { accentColor.opacity(0.55) }
    var glowColor: Color { accentColor.opacity(0.12) }   // very subtle
}

// MARK: - Glass card

struct GlassCard: ViewModifier {
    var radius: CGFloat = 20
    var glow: Color = .clear

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.borderHi, lineWidth: 0.5)
                    }
            }
            .shadow(color: glow, radius: 20)
    }
}

extension View {
    func glassCard(radius: CGFloat = 20, glow: Color = .clear) -> some View {
        modifier(GlassCard(radius: radius, glow: glow))
    }
}

// MARK: - Gradient text

extension View {
    func gradientForeground(_ colors: [Color], start: UnitPoint = .leading, end: UnitPoint = .trailing) -> some View {
        self.foregroundStyle(LinearGradient(colors: colors, startPoint: start, endPoint: end))
    }
}

// MARK: - Glow (low-intensity)

struct GlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.30), radius: radius * 0.35)
            .shadow(color: color.opacity(0.10), radius: radius * 0.7)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 16) -> some View {
        modifier(GlowModifier(color: color, radius: radius))
    }
}

// MARK: - Press button style

struct PressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Ambient background — static, no animation

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            // One faint tint in top-left corner — barely visible
            RadialGradient(
                colors: [Color(hex: "7B7EF8").opacity(0.055), .clear],
                center: .init(x: 0.3, y: 0.1),
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Animated border

struct AnimatedBorderModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let lineWidth: CGFloat
    @State private var hue: Double = 0

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [color, color.opacity(0.25), color.opacity(0.6), color],
                        center: .center,
                        startAngle: .degrees(hue),
                        endAngle: .degrees(hue + 360)
                    ),
                    lineWidth: lineWidth
                )
                .onAppear {
                    withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                        hue = 360
                    }
                }
        }
    }
}

extension View {
    func animatedBorder(color: Color, radius: CGFloat, lineWidth: CGFloat = 1) -> some View {
        modifier(AnimatedBorderModifier(color: color, radius: radius, lineWidth: lineWidth))
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                let w = geo.size.width
                LinearGradient(
                    colors: [.clear, .white.opacity(0.04), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: w * 2)
                .offset(x: w * phase)
                .onAppear {
                    withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            }
            .clipped()
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}
