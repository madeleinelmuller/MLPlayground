import SwiftUI

// MARK: - Liquid Glass Card

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    var material: Material = .ultraThinMaterial
    var strokeOpacity: Double = 0.25
    var shadowRadius: CGFloat = 20
    var tint: Color = .white
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(strokeOpacity * 2),
                                        tint.opacity(strokeOpacity * 0.3),
                                        tint.opacity(strokeOpacity)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: .black.opacity(0.25), radius: shadowRadius, y: 8)
    }
}

// MARK: - Glow modifier

extension View {
    func glowEffect(color: Color, radius: CGFloat = 12) -> some View {
        self
            .shadow(color: color.opacity(0.6), radius: radius / 2)
            .shadow(color: color.opacity(0.3), radius: radius)
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    var color: Color = .green
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .scaleEffect(scale)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                scale = 1.8
            }
        }
    }
}

// MARK: - Processing Ring

struct ProcessingRing: View {
    var color: Color
    var progress: Double = -1   // -1 = indeterminate
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            if progress < 0 {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AngularGradient(colors: [color, color.opacity(0)], center: .center),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(), value: progress)
            }
        }
    }
}

// MARK: - Tag Badge

struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(color.opacity(0.8))
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    )
            }
    }
}
