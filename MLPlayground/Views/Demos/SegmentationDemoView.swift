import SwiftUI
import AVFoundation

// MARK: - Segmentation Demo (DETR + DeepLabV3)

enum SegmentationMode { case detr, deeplab }

struct SegmentationDemoView: View {
    let task: MLTask
    let mode: SegmentationMode

    @Environment(LiveBackgroundState.self) private var liveBackground

    @State private var camera = CameraManager()
    @State private var detrProcessor = DETRProcessor()
    @State private var deepLabProcessor = DeepLabProcessor()
    @State private var segResult: SegmentationResult?
    @State private var overlayOpacity: Double = 0.65
    @State private var isRunning = false
    @State private var fps: Double = 0
    @State private var lastTime = Date()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(cameraManager: camera).ignoresSafeArea()

                if let result = segResult {
                    SegmentationOverlay(result: result, opacity: overlayOpacity)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: segResult?.mask)
                }

                VStack { Spacer(); bottomPanel(geo: geo) }
                    .padding(.bottom, 20)
            }
        }
        .task {
            if mode == .detr { await detrProcessor.loadIfNeeded() }
            else { await deepLabProcessor.loadIfNeeded() }
            await camera.start()
            isRunning = true
            await runSegLoop()
        }
        .onDisappear { camera.stop(); isRunning = false }
        // Feed segmentation result → live background
        .onChange(of: segResult?.classLabels) { _, _ in
            if let result = segResult {
                liveBackground.update(segResult: result)
            }
        }
    }

    // MARK: - Loop

    private func runSegLoop() async {
        while isRunning {
            guard let pb = camera.currentPixelBuffer else {
                try? await Task.sleep(nanoseconds: 33_000_000); continue
            }
            let result: SegmentationResult?
            if mode == .detr { result = await detrProcessor.segment(pixelBuffer: pb) }
            else              { result = await deepLabProcessor.segment(pixelBuffer: pb) }
            let now = Date()
            fps = 1.0 / max(now.timeIntervalSince(lastTime), 0.001)
            lastTime = now
            withAnimation(.easeInOut(duration: 0.1)) { segResult = result }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Bottom Panel

    private func bottomPanel(geo: GeometryProxy) -> some View {
        GlassCard(cornerRadius: 20, padding: 14, tint: task.primaryColor) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode == .detr ? "DETR ResNet-50" : "DeepLabV3")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        Text(mode == .detr ? "133-class panoptic" : "21-class VOC")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    FPSBadge(fps: fps)
                }

                HStack(spacing: 10) {
                    Image(systemName: "eye").font(.caption).foregroundStyle(.white.opacity(0.6))
                    Slider(value: $overlayOpacity, in: 0.1...1.0).tint(task.primaryColor)
                    Image(systemName: "eye.fill").font(.caption).foregroundStyle(.white.opacity(0.6))
                }

                if let result = segResult, !result.classLabels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(result.classLabels, id: \.self) { label in
                                HStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(result.classColors[label] ?? .gray)
                                        .frame(width: 10, height: 10)
                                    Text(label)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                    if let frac = result.classPixelFractions[label] {
                                        Text(String(format: "%.0f%%", frac * 100))
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.45))
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                ModelStatusBanner(task: task)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Segmentation Mask Overlay

struct SegmentationOverlay: View {
    let result: SegmentationResult
    let opacity: Double

    var body: some View {
        Image(decorative: result.mask, scale: 1)
            .resizable().scaledToFill()
            .opacity(opacity)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}
