import SwiftUI
import AVFoundation

// MARK: - FastViT Classification Demo

struct ClassificationDemoView: View {
    let task: MLTask

    @State private var camera = CameraManager()
    @State private var processor = FastViTProcessor()
    @State private var result: ClassificationResult?
    @State private var isRunning = false
    @State private var fps: Double = 0
    @State private var lastTime = Date()
    @State private var pulseRing: Bool = false
    @State private var topLabel: String = "—"
    @State private var topConf: Float = 0

    var body: some View {
        DemoShell(task: task) {
            GeometryReader { geo in
                ZStack {
                    // Camera feed
                    CameraPreview(cameraManager: camera).ignoresSafeArea()

                    // Central confidence ring
                    confidenceRing
                        .frame(width: 180, height: 180)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.38)

                    // Bottom panel with confidence bars
                    VStack {
                        Spacer()
                        bottomPanel
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .task {
            await processor.loadIfNeeded()
            await camera.start()
            isRunning = true
            await runClassifyLoop()
        }
        .onDisappear { camera.stop(); isRunning = false }
    }

    // MARK: - Loop

    private func runClassifyLoop() async {
        while isRunning {
            guard let pb = camera.currentPixelBuffer else {
                try? await Task.sleep(nanoseconds: 33_000_000)
                continue
            }
            let r = await processor.classify(pixelBuffer: pb)
            let now = Date()
            fps = 1.0 / max(now.timeIntervalSince(lastTime), 0.001)
            lastTime = now
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                result = r
                topLabel = r.topK.first?.label.capitalized ?? "—"
                topConf = r.topK.first?.confidence ?? 0
            }
            try? await Task.sleep(nanoseconds: 150_000_000)  // ~7 fps for classification
        }
    }

    // MARK: - Confidence Ring

    private var confidenceRing: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(task.primaryColor.opacity(0.1))
                .blur(radius: 20)
                .scaleEffect(pulseRing ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseRing)
                .onAppear { pulseRing = true }

            // Background ring
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 8)

            // Confidence arc
            Circle()
                .trim(from: 0, to: CGFloat(topConf))
                .stroke(
                    AngularGradient(
                        colors: [task.secondaryColor, task.primaryColor, task.secondaryColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: topConf)
                .glowEffect(color: task.primaryColor, radius: 8)

            // Inner glass card
            GlassCard(cornerRadius: 70, padding: 0, tint: task.primaryColor) {
                VStack(spacing: 4) {
                    Text("\(Int(topConf * 100))%")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                    Text(topLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: 100)
                        .contentTransition(.interpolate)
                }
                .frame(width: 140, height: 140)
            }
        }
    }

    // MARK: - Bottom Panel

    private var bottomPanel: some View {
        GlassCard(cornerRadius: 20, padding: 16, tint: task.primaryColor) {
            VStack(spacing: 12) {
                HStack {
                    Label("FastViT-T8", systemImage: "brain.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    FPSBadge(fps: fps)
                }

                if let result = result {
                    VStack(spacing: 8) {
                        ForEach(result.topK.prefix(5), id: \.label) { prediction in
                            ConfidenceBar(
                                label: prediction.label,
                                confidence: prediction.confidence,
                                accentColor: task.primaryColor,
                                isTop: prediction.label == topLabel
                            )
                        }
                    }
                }

                ModelStatusBanner(task: task)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Confidence Bar

struct ConfidenceBar: View {
    let label: String
    let confidence: Float
    let accentColor: Color
    let isTop: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label.capitalized)
                .font(.caption.weight(isTop ? .bold : .regular))
                .foregroundStyle(isTop ? .white : .white.opacity(0.7))
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isTop
                                    ? [accentColor.opacity(0.8), accentColor]
                                    : [.white.opacity(0.4), .white.opacity(0.5)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(confidence), height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: confidence)
                }
            }
            .frame(height: 6)

            Text(String(format: "%.1f%%", confidence * 100))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
