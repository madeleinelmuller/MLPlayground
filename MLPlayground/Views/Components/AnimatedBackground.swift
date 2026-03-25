import SwiftUI

// MARK: - Adaptive Animated Background

struct AnimatedBackground: View {
    let task: MLTask
    @State private var animPhase: Double = 0

    var body: some View {
        ZStack {
            // Base dark layer
            Color.black

            // Animated blobs
            ForEach(0..<4, id: \.self) { i in
                BlobShape(task: task, index: i, phase: animPhase)
            }

            // Noise/grain overlay for depth
            NoiseOverlay()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                animPhase = 1
            }
        }
    }
}

// MARK: - Animated Blob

private struct BlobShape: View {
    let task: MLTask
    let index: Int
    let phase: Double

    private var angle: Double { Double(index) * 90 + phase * 360 }
    private var radius: CGFloat { [0.35, 0.30, 0.25, 0.28][index % 4] }
    private var color: Color { [task.primaryColor, task.secondaryColor,
                                task.tertiaryColor, task.primaryColor][index % 4] }
    private var xOff: CGFloat { cos(angle * .pi / 180) * 180 }
    private var yOff: CGFloat { sin(angle * .pi / 180) * 160 }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.55), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: UIScreen.main.bounds.width * radius
                )
            )
            .scaleEffect(radius * 4.5)
            .offset(x: xOff, y: yOff)
            .blur(radius: 60)
            .animation(
                .easeInOut(duration: 6 + Double(index) * 1.5).repeatForever(autoreverses: true),
                value: phase
            )
    }
}

// MARK: - Noise overlay

private struct NoiseOverlay: View {
    var body: some View {
        // Simulated grain via canvas
        Canvas { context, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<3000 {
                let x = CGFloat.random(in: 0..<size.width, using: &rng)
                let y = CGFloat.random(in: 0..<size.height, using: &rng)
                let alpha = Double.random(in: 0.01...0.06, using: &rng)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Task Color Background (static transition version)

struct TaskColorBackground: View {
    let task: MLTask
    @State private var appear = false

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                task.primaryColor.opacity(0.25),
                .black,
                task.secondaryColor.opacity(0.15)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) { appear = true }
        }
    }
}
