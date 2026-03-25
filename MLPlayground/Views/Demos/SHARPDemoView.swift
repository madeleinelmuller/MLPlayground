import SwiftUI
import PhotosUI

// MARK: - SHARP 3D View Synthesis Demo

struct SHARPDemoView: View {
    let task: MLTask

    @State private var processor = SHARPProcessor()
    @State private var camera = CameraManager()
    @State private var selectedPhoto: UIImage?
    @State private var photoPicker: PhotosPickerItem?
    @State private var renderedFrame: SHARPFrame?
    @State private var isProcessing = false
    @State private var angleH: Float = 0
    @State private var angleV: Float = 0
    @State private var dragStart: SIMD2<Float>?
    @State private var phase: Double = 0
    @State private var mode: InputMode = .camera
    @State private var showCaptureTip = true

    enum InputMode { case camera, photo }

    var body: some View {
        DemoShell(task: task) {
            GeometryReader { geo in
                ZStack {
                    // Image display
                    imageLayer(geo: geo)

                    // Gaussian splat overlay
                    if renderedFrame != nil {
                        gaussianParticles(in: geo)
                    }

                    // 3D angle HUD
                    if processor.isProcessed {
                        angleHUD
                            .position(x: geo.size.width / 2, y: 100)
                    }

                    // Bottom panel
                    VStack {
                        Spacer()
                        bottomPanel(geo: geo)
                    }
                    .padding(.bottom, 20)
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let dx = Float(value.translation.width) * 0.3
                            let dy = Float(value.translation.height) * 0.2
                            angleH = max(-45, min(45, dx))
                            angleV = max(-20, min(20, dy))
                            renderCurrentAngle()
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                                angleH = 0; angleV = 0
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                renderCurrentAngle()
                            }
                        }
                )
            }
        }
        .task {
            await camera.start()
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .onDisappear { camera.stop() }
        .onChange(of: photoPicker) { _, item in
            Task { await loadPhoto(item) }
        }
    }

    // MARK: - Image Layer

    @ViewBuilder
    private func imageLayer(geo: GeometryProxy) -> some View {
        if let frame = renderedFrame {
            Image(uiImage: frame.rendered)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
                .rotation3DEffect(
                    .degrees(Double(angleH) * 0.15),
                    axis: (x: 0, y: 1, z: 0)
                )
                .rotation3DEffect(
                    .degrees(Double(angleV) * 0.1),
                    axis: (x: 1, y: 0, z: 0)
                )
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.75), value: angleH)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.75), value: angleV)
        } else if let photo = selectedPhoto {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
                .overlay { processingOverlay }
        } else {
            CameraPreview(cameraManager: camera)
                .ignoresSafeArea()
                .overlay {
                    if showCaptureTip {
                        captureTip
                            .transition(.opacity)
                    }
                }
        }
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        Group {
            if isProcessing {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 16) {
                        ProcessingRing(color: task.primaryColor)
                            .frame(width: 60, height: 60)
                        Text("Fitting Gaussians…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Gaussian particles overlay

    @ViewBuilder
    private func gaussianParticles(in geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            let count = 80
            for i in 0..<count {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let r = CGFloat.random(in: 1.5...5)
                let alpha = Double.random(in: 0.1...0.4) * abs(sin(phase * .pi + Double(i) * 0.3))
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(task.primaryColor.opacity(alpha))
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Angle HUD

    private var angleHUD: some View {
        GlassCard(cornerRadius: 14, padding: 10, tint: task.primaryColor) {
            HStack(spacing: 12) {
                Label(String(format: "H %.0f°", angleH), systemImage: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Label(String(format: "V %.0f°", angleV), systemImage: "arrow.up.and.down")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("\(processor.isProcessed ? "~4096" : "0") splats")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Capture tip

    private var captureTip: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 40))
                .foregroundStyle(task.primaryColor)
                .glowEffect(color: task.primaryColor, radius: 20)
            Text("Capture a photo or pick\none from your library")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    // MARK: - Bottom Panel

    private func bottomPanel(geo: GeometryProxy) -> some View {
        GlassCard(cornerRadius: 20, padding: 16, tint: task.primaryColor) {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHARP")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("3D Gaussian Splatting")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if processor.isProcessed {
                        TagBadge(text: "Drag to orbit", color: task.primaryColor)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Capture from camera
                    Button {
                        captureAndProcess(geo: geo)
                    } label: {
                        Label("Capture", systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(task.primaryColor.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Photo picker
                    PhotosPicker(selection: $photoPicker, matching: .images) {
                        Label("Gallery", systemImage: "photo.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                    }
                }

                // Architecture note
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Simulated Gaussian splatting. Real SHARP model pending Core ML conversion.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func captureAndProcess(geo: GeometryProxy) {
        guard let cgImage = camera.currentFrame else { return }
        let uiImage = UIImage(cgImage: cgImage)
        selectedPhoto = uiImage
        showCaptureTip = false
        Task { await fitModel(image: uiImage) }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            selectedPhoto = uiImage
            showCaptureTip = false
            await fitModel(image: uiImage)
        }
    }

    private func fitModel(image: UIImage) async {
        isProcessing = true
        await processor.fit(image: image)
        isProcessing = false
        renderCurrentAngle()
    }

    private func renderCurrentAngle() {
        guard processor.isProcessed else { return }
        if let frame = processor.render(angleH: angleH, angleV: angleV) {
            renderedFrame = frame
        }
    }
}
