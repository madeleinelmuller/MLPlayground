import SwiftUI
import AVFoundation

// MARK: - YOLOv3 Object Detection Demo

struct YOLODemoView: View {
    let task: MLTask

    @Environment(LiveBackgroundState.self) private var liveBackground

    @State private var camera = CameraManager()
    @State private var processor = YOLOProcessor()
    @State private var detections: [DetectedObject] = []
    @State private var isRunning = false
    @State private var fps: Double = 0
    @State private var lastFrameTime = Date()
    @State private var processingFrame = false
    @State private var selectedDetection: DetectedObject?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(cameraManager: camera).ignoresSafeArea()

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

                VStack {
                    Spacer()
                    hudPanel
                }
                .padding(.bottom, 20)
            }
        }
        .task {
            await processor.loadIfNeeded()
            await camera.start()
            isRunning = true
            await runDetectionLoop()
        }
        .onDisappear { camera.stop(); isRunning = false }
        // Feed detections → live background
        .onChange(of: detections) { _, new in
            liveBackground.update(detections: new)
        }
    }

    // MARK: - Detection loop

    private func runDetectionLoop() async {
        while isRunning {
            guard !processingFrame, let pb = camera.currentPixelBuffer else {
                await Task.yield(); continue
            }
            processingFrame = true
            let result = await processor.detect(in: pb)
            let now = Date()
            let dt = now.timeIntervalSince(lastFrameTime)
            lastFrameTime = now
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                detections = result
                fps = 1.0 / max(dt, 0.001)
            }
            processingFrame = false
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - HUD

    private var hudPanel: some View {
        GlassCard(cornerRadius: 20, padding: 14, tint: task.primaryColor) {
            VStack(spacing: 10) {
                HStack {
                    Label("\(detections.count) object\(detections.count == 1 ? "" : "s")",
                          systemImage: "viewfinder.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    ModelStatusBanner(task: task)
                    FPSBadge(fps: fps)
                }
                if !detections.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detections) { d in
                                TagBadge(text: "\(d.label) \(Int(d.confidence * 100))%", color: d.color)
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
        CGRect(x: detection.boundingBox.minX * containerSize.width,
               y: detection.boundingBox.minY * containerSize.height,
               width: detection.boundingBox.width * containerSize.width,
               height: detection.boundingBox.height * containerSize.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(detection.color, lineWidth: isSelected ? 3 : 2)
                .frame(width: rect.width, height: rect.height)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6).fill(detection.color.opacity(0.15))
                    }
                }

            CornerAccents(color: detection.color, size: 12)
                .frame(width: rect.width, height: rect.height)

            HStack(spacing: 4) {
                Text(detection.label).font(.system(size: 11, weight: .bold))
                Text("\(Int(detection.confidence * 100))%")
                    .font(.system(size: 10, weight: .medium)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(detection.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 5))
            .offset(y: -22)
        }
        .position(x: rect.midX, y: rect.midY)
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { appear = true }
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
                cornerPath(geo, .topLeft).stroke(color, lineWidth: 2)
                cornerPath(geo, .topRight).stroke(color, lineWidth: 2)
                cornerPath(geo, .bottomLeft).stroke(color, lineWidth: 2)
                cornerPath(geo, .bottomRight).stroke(color, lineWidth: 2)
            }
        }
    }

    private enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private func cornerPath(_ geo: GeometryProxy, _ c: Corner) -> Path {
        let w = geo.size.width, h = geo.size.height, s = size
        return Path { p in
            switch c {
            case .topLeft:
                p.move(to: CGPoint(x: 0, y: s)); p.addLine(to: .zero)
                p.addLine(to: CGPoint(x: s, y: 0))
            case .topRight:
                p.move(to: CGPoint(x: w - s, y: 0)); p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: s))
            case .bottomLeft:
                p.move(to: CGPoint(x: 0, y: h - s)); p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: s, y: h))
            case .bottomRight:
                p.move(to: CGPoint(x: w - s, y: h)); p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w, y: h - s))
            }
        }
    }
}
