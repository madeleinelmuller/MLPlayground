import SwiftUI
import ARKit
import SceneKit

// MARK: - SpatialLM Spatial Scene Understanding Demo

struct SpatialLMDemoView: View {
    let task: MLTask

    @Environment(LiveBackgroundState.self) private var liveBackground

    @State private var processor = SpatialLMProcessor()
    @State private var sceneResult: SpatialResult?
    @State private var viewMode: ViewMode = .ar
    @State private var rotationAngle: Double = 0
    @State private var phase: Double = 0

    enum ViewMode: String, CaseIterable {
        case ar = "AR View"
        case map = "Scene Map"
        case list = "Object List"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch viewMode {
                case .ar:   arView(geo: geo)
                case .map:  sceneMapView(geo: geo)
                case .list: listView(geo: geo)
                }

                VStack { Spacer(); bottomPanel(geo: geo) }
                    .padding(.bottom, 20)
            }
        }
        .task {
            processor.onSceneUpdate = { result in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    sceneResult = result
                }
                // Feed 3D object layout → live background
                liveBackground.update(spatial: result)
            }
            processor.start()
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotationAngle = 360; phase = 1
            }
        }
        .onDisappear { processor.stop() }
    }

    // MARK: - AR View

    @ViewBuilder
    private func arView(geo: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            StarField(phase: phase).ignoresSafeArea()

            if let result = sceneResult {
                ForEach(Array(result.objects.enumerated()), id: \.1.id) { idx, obj in
                    FloatingBox3D(object: obj, index: idx, phase: phase, geo: geo)
                }

                VStack {
                    GlassCard(cornerRadius: 14, padding: 12, tint: task.primaryColor) {
                        Text(result.roomDescription)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 30)
                    Spacer()
                }
                .padding(.top, 90)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Scene Map

    @ViewBuilder
    private func sceneMapView(geo: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GridFloor(color: task.primaryColor.opacity(0.3)).ignoresSafeArea()

            if let result = sceneResult {
                let scale: CGFloat = geo.size.width / 6.0
                let cx = geo.size.width / 2
                let cy = geo.size.height * 0.45

                ForEach(result.objects) { obj in
                    let bx = cx + CGFloat(obj.center.x) * scale
                    let by = cy + CGFloat(obj.center.z) * scale
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(obj.color.opacity(0.4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(obj.color, lineWidth: 1.5))
                            .frame(width: CGFloat(obj.extent.x) * scale,
                                   height: CGFloat(obj.extent.z) * scale)
                            .rotationEffect(.degrees(Double(obj.yaw) * 180 / .pi))
                        Text(obj.label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                    .position(x: bx, y: by)
                    .animation(.spring(response: 0.5), value: obj.center)
                }

                ZStack {
                    Circle().fill(.white)
                    Image(systemName: "camera.fill").font(.system(size: 8)).foregroundStyle(.black)
                }
                .frame(width: 20, height: 20)
                .position(x: cx, y: cy + 40)
                .glowEffect(color: .white, radius: 10)
            }

            HStack {
                Text("2m").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Rectangle().fill(.white.opacity(0.4)).frame(width: geo.size.width / 3, height: 1)
                Text("2m").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 150)
        }
    }

    // MARK: - List View

    @ViewBuilder
    private func listView(geo: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 8) {
                    if let result = sceneResult {
                        ForEach(Array(result.objects.enumerated()), id: \.1.id) { idx, obj in
                            objectRow(obj: obj, index: idx)
                        }
                    } else {
                        ProgressView().tint(task.primaryColor).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 160)
            }
            .padding(.top, 80)
        }
    }

    private func objectRow(obj: SpatialResult.BoundingBox3D, index: Int) -> some View {
        GlassCard(cornerRadius: 14, padding: 12, tint: obj.color) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(obj.color.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: iconForLabel(obj.label))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))

                VStack(alignment: .leading, spacing: 2) {
                    Text(obj.label.capitalized)
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    Text(String(format: "%.1f × %.1f × %.1f m",
                                obj.extent.x, obj.extent.y, obj.extent.z))
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "(%.1f, %.1f)", obj.center.x, obj.center.z))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(String(format: "%.0f°", obj.yaw * 180 / .pi))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    // MARK: - Bottom Panel

    private func bottomPanel(geo: GeometryProxy) -> some View {
        VStack(spacing: 10) {
            GlassCard(cornerRadius: 16, padding: 6, tint: task.primaryColor) {
                HStack(spacing: 0) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewMode = mode
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(mode.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(viewMode == mode ? .black : .white.opacity(0.7))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background { if viewMode == mode { Capsule().fill(.white) } }
                        }
                    }
                }
            }
            GlassCard(cornerRadius: 20, padding: 12, tint: task.primaryColor) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SpatialLM").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        Text(processor.isLiDARAvailable ? "LiDAR active" : "ARKit simulation")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    if let r = sceneResult {
                        TagBadge(text: "\(r.objects.count) objects", color: task.primaryColor)
                    }
                    if processor.isLiDARAvailable { PulsingDot(color: .green) }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func iconForLabel(_ label: String) -> String {
        let map = ["chair": "chair", "table": "table.furniture", "sofa": "sofa",
                   "bed": "bed.double", "tv": "tv", "lamp": "lamp.floor",
                   "plant": "leaf", "door": "door.sliding.open", "window": "window.ceiling"]
        return map[label] ?? "cube"
    }
}

// MARK: - Floating 3D Box

private struct FloatingBox3D: View {
    let object: SpatialResult.BoundingBox3D
    let index: Int
    let phase: Double
    let geo: GeometryProxy
    @State private var offset: CGFloat = 0

    private var xPos: CGFloat { geo.size.width  * 0.5 + CGFloat(object.center.x) * 50 }
    private var yPos: CGFloat { geo.size.height * 0.45 + CGFloat(object.center.z) * 40 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(object.color.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(object.color.opacity(0.8), lineWidth: 1.5))
                .frame(width: CGFloat(object.extent.x) * 55,
                       height: CGFloat(object.extent.y) * 55)
                .glowEffect(color: object.color, radius: 8)
            VStack(spacing: 3) {
                Image(systemName: "cube.transparent").font(.system(size: 10)).foregroundStyle(object.color)
                Text(object.label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
        }
        .position(x: xPos, y: yPos + offset)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.5 + Double(index) * 0.4)
                .repeatForever(autoreverses: true)
            ) { offset = CGFloat.random(in: -8...8) }
        }
    }
}

// MARK: - Grid Floor

private struct GridFloor: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 40
            for x in stride(from: 0, to: size.width, by: step) {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(color), lineWidth: 0.5)
            }
            for y in stride(from: 0, to: size.height, by: step) {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(color), lineWidth: 0.5)
            }
        }
    }
}

// MARK: - Star Field

private struct StarField: View {
    let phase: Double
    var body: some View {
        Canvas { ctx, size in
            var rng = SystemRandomNumberGenerator()
            for i in 0..<120 {
                let x = CGFloat.random(in: 0..<size.width, using: &rng)
                let y = CGFloat.random(in: 0..<size.height, using: &rng)
                let r = CGFloat.random(in: 0.5...2, using: &rng)
                let a = Double.random(in: 0.2...0.8, using: &rng) *
                    abs(sin(phase * .pi * 2 + Double(i) * 0.01))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(.white.opacity(a)))
            }
        }
    }
}
