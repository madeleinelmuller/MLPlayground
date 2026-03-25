import SwiftUI
import AVFoundation

// MARK: - Depth Anything V2 Demo

struct DepthDemoView: View {
    let task: MLTask

    @State private var camera = CameraManager()
    @State private var processor = DepthProcessor()
    @State private var depthResult: DepthResult?
    @State private var showOriginal = false
    @State private var isRunning = false
    @State private var fps: Double = 0
    @State private var lastTime = Date()
    @State private var wavePhase: Double = 0

    var body: some View {
        DemoShell(task: task) {
            GeometryReader { geo in
                ZStack {
                    // Base layer
                    if showOriginal {
                        CameraPreview(cameraManager: camera).ignoresSafeArea()
                    } else if let result = depthResult {
                        // Depth map (false colour)
                        Image(decorative: result.depthMap, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.2), value: showOriginal)
                    } else {
                        CameraPreview(cameraManager: camera).ignoresSafeArea()
                    }

                    // Wave scan line animation
                    if !showOriginal {
                        ScanlineAnimation(color: task.primaryColor, phase: wavePhase)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    // Colour ramp legend (right edge)
                    VStack {
                        colourRampLegend
                            .padding(.top, 80)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)

                    // Bottom panel
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
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                wavePhase = 1
            }
            await runDepthLoop()
        }
        .onDisappear { camera.stop(); isRunning = false }
    }

    // MARK: - Loop

    private func runDepthLoop() async {
        while isRunning {
            guard let pb = camera.currentPixelBuffer else {
                try? await Task.sleep(nanoseconds: 33_000_000)
                continue
            }
            let result = await processor.estimateDepth(pixelBuffer: pb)
            let now = Date()
            fps = 1.0 / max(now.timeIntervalSince(lastTime), 0.001)
            lastTime = now
            withAnimation(.easeInOut(duration: 0.1)) { depthResult = result }
            try? await Task.sleep(nanoseconds: 80_000_000)  // ~12 fps
        }
    }

    // MARK: - Colour ramp legend

    private var colourRampLegend: some View {
        VStack(spacing: 0) {
            Text("Far")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            LinearGradient(
                colors: [
                    Color(hue: 0.67, saturation: 0.9, brightness: 0.9),   // far (blue)
                    Color(hue: 0.33, saturation: 0.9, brightness: 0.9),   // mid (green)
                    Color(hue: 0.08, saturation: 1.0, brightness: 1.0),   // near (orange)
                    Color(hue: 0.00, saturation: 1.0, brightness: 0.9),   // nearest (red)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 14, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.3), lineWidth: 0.5))

            Text("Near")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        GlassCard(cornerRadius: 20, padding: 14, tint: task.primaryColor) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Depth Anything V2 Small")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        if let r = depthResult {
                            Text(String(format: "Range: %.1f – %.1f m", r.minDepth, r.maxDepth))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Spacer()
                    FPSBadge(fps: fps)
                }

                // Toggle original/depth
                Toggle(isOn: $showOriginal) {
                    Label("Show original", systemImage: "camera")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .toggleStyle(SwitchToggleStyle(tint: task.primaryColor))

                ModelStatusBanner(task: task)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Scan Line Animation

private struct ScanlineAnimation: View {
    let color: Color
    let phase: Double

    var body: some View {
        GeometryReader { geo in
            let y = phase * geo.size.height
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, color.opacity(0.5), color.opacity(0.8), color.opacity(0.5), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(height: 40)
                .offset(y: y)
                .blur(radius: 2)
        }
    }
}
