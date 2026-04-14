import SwiftUI

struct OnboardingView: View {
    @Binding var isDone: Bool
    @State private var appeared = false
    @State private var orbFloat = false
    @State private var ctaBreathe = false

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                Spacer()
                heroSection
                Spacer()
                featuresSection
                Spacer()
                ctaButton
                    .padding(.bottom, 52)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.65).delay(0.1)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true).delay(0.8)) {
                orbFloat = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(1.6)) {
                ctaBreathe = true
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 24) {
            ZStack {
                // Glow halo — floats
                Circle()
                    .fill(Color.violet.opacity(0.07))
                    .frame(width: 180, height: 180)
                    .blur(radius: 28)
                    .scaleEffect(orbFloat ? 1.12 : 0.92)

                // Ring
                Circle()
                    .strokeBorder(Color.violet.opacity(orbFloat ? 0.55 : 0.3), lineWidth: 1)
                    .frame(width: 114, height: 114)

                // Icon floats
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48, weight: .thin))
                    .gradientForeground([.white, Color.violet], start: .top, end: .bottom)
                    .offset(y: orbFloat ? -5 : 3)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.55)

            VStack(spacing: 10) {
                Text("LocalAI")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .gradientForeground([.white, Color.violet.opacity(0.8)])
                    .glow(Color.violet, radius: 16)

                Text("Нейросеть прямо\nна твоём iPhone")
                    .font(.system(size: 20, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.txt2)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 12) {
            OnboardingFeature(icon: "lock.fill", color: Color(hex: "34C759"),
                              title: "100% приватно",
                              subtitle: "Данные не покидают устройство никогда", delay: 0.12)
            OnboardingFeature(icon: "wifi.slash", color: Color.orange,
                              title: "Полный офлайн",
                              subtitle: "Работает без интернета после загрузки", delay: 0.22)
            OnboardingFeature(icon: "sparkles", color: Color.violet,
                              title: "Уровень GPT-3.5",
                              subtitle: "Мощные 7B модели прямо на iPhone", delay: 0.32)
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { isDone = true }
        } label: {
            HStack(spacing: 10) {
                Text("Начать")
                    .font(.system(size: 18, weight: .bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .offset(x: ctaBreathe ? 3 : 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.violet)
                    .opacity(ctaBreathe ? 1.0 : 0.88)
                    .glow(Color.violet, radius: ctaBreathe ? 18 : 10)
            }
        }
        .buttonStyle(PressButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .scaleEffect(appeared ? 1 : 0.9)
    }
}

private struct OnboardingFeature: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let delay: Double
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.13))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
                    .scaleEffect(appeared ? 1 : 0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.txt1)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.txt2)
            }
            Spacer()
        }
        .padding(16)
        .glassCard(radius: 16)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -28)
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.68).delay(delay + 0.35)) {
                appeared = true
            }
        }
    }
}
