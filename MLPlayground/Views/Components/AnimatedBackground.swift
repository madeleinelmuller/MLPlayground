import SwiftUI

// MARK: - Adaptive Animated Background
// Two layers:
//   1. Slow-drifting task-coloured blobs (always visible, low opacity)
//   2. Live blobs driven by current ML output (fade in once results arrive)

struct AnimatedBackground: View {
    let task: MLTask
    /// Inject via the DemoShell environment; nil = home screen default.
    var liveState: LiveBackgroundState? = nil

    @State private var animPhase: Double = 0
    @State private var liveLayerOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black

            // ── Layer 1: ambient task-colour blobs ──
            ForEach(0..<4, id: \.self) { i in
                AmbientBlob(task: task, index: i, phase: animPhase)
            }

            // ── Layer 2: live ML-driven blobs ──
            if let state = liveState {
                LiveLayer(state: state)
                    .opacity(liveLayerOpacity)
                    .onChange(of: state.isActive) { _, active in
                        withAnimation(.easeInOut(duration: 0.55)) {
                            liveLayerOpacity = active ? 1.0 : 0.0
                        }
                    }
            }

            // Subtle film-grain
            GrainOverlay()
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                animPhase = 1
            }
        }
    }
}

// MARK: - Ambient task-coloured blob (slow orbit)

private struct AmbientBlob: View {
    let task: MLTask
    let index: Int
    let phase: Double

    private var angle: Double { Double(index) * 90 + phase * 360 }
    private var radius: CGFloat { [0.30, 0.26, 0.22, 0.28][index % 4] }
    private var color: Color {
        [task.primaryColor, task.secondaryColor,
         task.tertiaryColor, task.primaryColor][index % 4]
    }
    private var xOff: CGFloat { cos(angle * .pi / 180) * 170 }
    private var yOff: CGFloat { sin(angle * .pi / 180) * 140 }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.38), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: UIScreen.main.bounds.width * radius
                )
            )
            .scaleEffect(radius * 4.2)
            .offset(x: xOff, y: yOff)
            .blur(radius: 55)
            .animation(
                .easeInOut(duration: 7 + Double(index) * 1.8)
                .repeatForever(autoreverses: true),
                value: phase
            )
    }
}

// MARK: - Live ML-result layer

private struct LiveLayer: View {
    let state: LiveBackgroundState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(state.blobs.enumerated()), id: \.0) { i, blob in
                    if blob.weight > 0.01 {
                        LiveBlobShape(blob: blob, containerSize: geo.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Individual live blob

private struct LiveBlobShape: View {
    let blob: LiveBackgroundState.Blob
    let containerSize: CGSize

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        blob.color.opacity(0.55 * blob.weight),
                        blob.color.opacity(0.12 * blob.weight),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: blobRadius
                )
            )
            .frame(width: blobRadius * 2, height: blobRadius * 2)
            .blur(radius: 40 + CGFloat(blob.weight) * 50)
            .position(blobCenter)
            // Animate position and size changes
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: blob.x)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: blob.y)
            .animation(.easeInOut(duration: 0.35), value: blob.weight)
    }

    private var blobRadius: CGFloat {
        let base = min(containerSize.width, containerSize.height)
        return CGFloat(blob.weight * 0.55 + 0.18) * base * 0.75
    }

    private var blobCenter: CGPoint {
        CGPoint(
            x: CGFloat(blob.x) * containerSize.width,
            y: CGFloat(blob.y) * containerSize.height
        )
    }
}

// MARK: - Film grain overlay

private struct GrainOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<2500 {
                let x = CGFloat.random(in: 0..<size.width, using: &rng)
                let y = CGFloat.random(in: 0..<size.height, using: &rng)
                let a = Double.random(in: 0.01...0.055, using: &rng)
                ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                         with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Home-screen standalone background (no live state)

struct TaskColorBackground: View {
    let task: MLTask
    @State private var appear = false

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                task.primaryColor.opacity(0.22),
                .black,
                task.secondaryColor.opacity(0.14)
            ]),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.55)) { appear = true }
        }
    }
}
