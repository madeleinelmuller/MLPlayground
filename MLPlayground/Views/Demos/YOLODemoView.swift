import SwiftUI
import AVFoundation

// MARK: - YOLOv3 Object Detection Demo

struct YOLODemoView: View {
    let task: MLTask

    @State private var camera = CameraManager()
    @State private var processor = YOLOProcessor()
    @State private var detections: [DetectedObject] = []
    @State private var isRunning = false
    @State private var fps: Double = 0
    @State private var lastFrameTime = Date()
    @State private var processingFrame = false
    @State private var selectedDetection: DetectedObject?

    var body: some View {
        DemoShell(task: task) {
            GeometryReader { geo in
                ZStack {
                    // Camera feed
                    CameraPreview(cameraManager: camera)
                        .ignoresSafeArea()

                    // Detection overlays
                    ForEach(detections) { detection in
                        BoundingBoxView(detection: detection,
                                        containerSize: geo.size,
                                        isSelected: selectedDetection?.id == detection.id)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedDetection = (selectedDetection?.id == detection.id) ? nil : detection
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    }

                    // HUD overlay
                    VStack {
                        Spacer()
                        hudPanel(containerSize: geo.size)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .task {
            await processor.loadIfNeeded()
            await camera.start()
            isRunning = true
            await runDetectionLoop()
        }
        .onDisappear { camera.stop(); isRunning = false }
    }

    // MARK: - Detection loop

    private func runDetectionLoop() async {
        while isRunning {
            guard !processingFrame,
                  let pixelBuffer = camera.currentPixelBuffer else {
                await Task.yield()
                continue
            }
            processingFrame = true
            let result = await processor.detect(in: pixelBuffer)
            let now = Date()
            let dt = now.timeIntervalSince(lastFrameTime)
            lastFrameTime = now

            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                detections = result
                fps = 1.0 / max(dt, 0.001)
            }
            processingFrame = false
            try? await Task.sleep(nanoseconds: 50_000_000)   // ~20 FPS cap
        }
    }

    // MARK: - HUD

    private func hudPanel(containerSize: CGSize) -> some View {
        GlassCard(cornerRadius: 20, padding: 14, tint: task.primaryColor) {
            VStack(spacing: 10) {
                // Stats row
                HStack {
                    Label("\(detections.count) object\(detections.count == 1 ? "" : "s")",
                          systemImage: "viewfinder.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    ModelStatusBanner(task: task)
                    FPSBadge(fps: fps)
                }

                // Detected classes scroll
                if !detections.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detections) { d in
                                TagBadge(
                                    text: "\(d.label) \(Int(d.confidence * 100))%",
                                    color: d.color
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedDetection = (selectedDetection?.id == d.id) ? nil : d
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Bounding Box Overlay

struct BoundingBoxView: View {
    let detection: DetectedObject
    let containerSize: CGSize
    let isSelected: Bool

    @State private var appear = false

    private var rect: CGRect {
        CGRect(
            x: detection.boundingBox.minX * containerSize.width,
            y: detection.boundingBox.minY * containerSize.height,
            width: detection.boundingBox.width * containerSize.width,
            height: detection.boundingBox.height * containerSize.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Box
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(detection.color, lineWidth: isSelected ? 3 : 2)
                .frame(width: rect.width, height: rect.height)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(detection.color.opacity(0.15))
                    }
                }

            // Corner accents
            CornerAccents(color: detection.color, size: 12)
                .frame(width: rect.width, height: rect.height)

            // Label tag
            HStack(spacing: 4) {
                Text(detection.label)
                    .font(.system(size: 11, weight: .bold))
                Text("\(Int(detection.confidence * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(detection.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            .offset(y: -22)
        }
        .position(x: rect.midX, y: rect.midY)
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { appear = true }
        }
        .onChange(of: detection.boundingBox) { _, _ in
            // Keep smooth when box updates
        }
    }
}

// MARK: - Corner Accents

private struct CornerAccents: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // TL
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size))
                    p.addLine(to: .zero)
                    p.addLine(to: CGPoint(x: size, y: 0))
                }.stroke(color, lineWidth: 2)

                // TR
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - size, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    p.addLine(to: CGPoint(x: geo.size.width, y: size))
                }.stroke(color, lineWidth: 2)

                // BL
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - size))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.addLine(to: CGPoint(x: size, y: geo.size.height))
                }.stroke(color, lineWidth: 2)

                // BR
                Path { p in
                    p.move(to: CGPoint(x: geo.size.width - size, y: geo.size.height))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - size))
                }.stroke(color, lineWidth: 2)
            }
        }
    }
}
