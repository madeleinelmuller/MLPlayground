import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @State private var selectedTask: MLTask?
    @State private var headerAppear = false
    @Namespace private var heroNamespace

    let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                // Adaptive animated background
                if let task = selectedTask {
                    AnimatedBackground(task: task)
                        .transition(.opacity)
                } else {
                    defaultBackground
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        headerSection
                        taskGrid
                        footerNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedTask) { task in
                demoView(for: task)
                    .navigationBarBackButtonHidden()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ML Playground")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("7 models · live on device")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                // Animated logo mark
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: 52, height: 52)
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .glowEffect(color: .white, radius: 20)
            }
        }
        .padding(.top, 60)
        .opacity(headerAppear ? 1 : 0)
        .offset(y: headerAppear ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                headerAppear = true
            }
        }
    }

    // MARK: - Grid

    private var taskGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(MLTask.allCases.enumerated()), id: \.1.id) { index, task in
                TaskCard(task: task, onTap: {
                    selectedTask = task
                })
                    .matchedGeometryEffect(id: task.id, in: heroNamespace)
                    .opacity(headerAppear ? 1 : 0)
                    .offset(y: headerAppear ? 0 : 30)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.8)
                        .delay(0.15 + Double(index) * 0.06),
                        value: headerAppear
                    )
            }
        }
    }

    // MARK: - Footer

    private var footerNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
            Text("All inference runs entirely on-device.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.top, 4)
    }

    // MARK: - Default background

    private var defaultBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Multi-color radial gradient hints
            RadialGradient(
                colors: [Color(hue: 0.72, saturation: 0.8, brightness: 0.4).opacity(0.4), .clear],
                center: .topLeading, startRadius: 0, endRadius: 400
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(hue: 0.57, saturation: 0.8, brightness: 0.5).opacity(0.3), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 350
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Demo Routing

    @ViewBuilder
    private func demoView(for task: MLTask) -> some View {
        switch task {
        case .sharp:     SHARPDemoView(task: task)
        case .detr:      SegmentationDemoView(task: task, mode: .detr)
        case .deeplab:   SegmentationDemoView(task: task, mode: .deeplab)
        case .yolo:      YOLODemoView(task: task)
        case .depth:     DepthDemoView(task: task)
        case .fastvit:   ClassificationDemoView(task: task)
        case .spatialLM: SpatialLMDemoView(task: task)
        }
    }
}

#Preview {
    HomeView()
}
