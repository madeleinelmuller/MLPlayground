import SwiftUI

// MARK: - Shared Demo Shell
// Creates a LiveBackgroundState, passes it to AnimatedBackground, and injects
// it into the environment so every child demo view can feed results to it.

struct DemoShell<Content: View>: View {
    let task: MLTask
    @Environment(\.dismiss) private var dismiss

    /// Single source of truth for the live background.
    @State private var liveBackground = LiveBackgroundState()

    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            // Background reads liveBackground directly via @Observable
            AnimatedBackground(task: task, liveState: liveBackground)

            content()
                .padding(.top, 70)
                // Inject so demo views can write to liveBackground
                .environment(liveBackground)

            navBar
        }
        .ignoresSafeArea()
        .statusBarHidden(false)
    }

    // MARK: - Navigation bar

    private var navBar: some View {
        HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.15), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(task.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            Image(systemName: task.systemIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(task.primaryColor.opacity(0.6), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                .glowEffect(color: task.primaryColor, radius: 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.black.opacity(0.7), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Model Status Banner

struct ModelStatusBanner: View {
    let task: MLTask

    var body: some View {
        let state = MLModelManager.shared.state(for: task)
        Group {
            switch state {
            case .downloading(let p):
                statusRow(icon: "arrow.down.circle.fill",
                          text: "Downloading… \(Int(p * 100))%",
                          color: task.primaryColor)
            case .loading:
                statusRow(icon: "cpu.fill", text: "Compiling…", color: task.secondaryColor)
            case .failed(let msg):
                statusRow(icon: "exclamationmark.triangle.fill",
                          text: msg.isEmpty ? "Demo mode — model unavailable" : msg,
                          color: .orange)
            case .ready, .idle:
                EmptyView()
            }
        }
    }

    private func statusRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - FPS badge

struct FPSBadge: View {
    let fps: Double
    var body: some View {
        Text(String(format: "%.0f FPS", fps))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.green)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().strokeBorder(.green.opacity(0.4), lineWidth: 0.5))
    }
}
