import SwiftUI

// MARK: - Task Card (home grid cell)

struct TaskCard: View {
    let task: MLTask
    var isSelected: Bool = false
    var onTap: () -> Void = {}
    @State private var hovered = false
    @State private var iconBounce: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background gradient
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            task.primaryColor.opacity(0.80),
                            task.secondaryColor.opacity(0.50),
                            task.tertiaryColor.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle inner glow at top
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.18), .clear],
                        center: .init(x: 0.3, y: 0.1),
                        startRadius: 0,
                        endRadius: 120
                    )
                )

            // Glass stroke
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            // Large icon (background)
            Image(systemName: task.systemIcon)
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.07))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Floating icon
                Image(systemName: task.systemIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                    }
                    .offset(y: iconBounce)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 2 + Double(task.allCases.firstIndex(of: task) ?? 0) * 0.3)
                            .repeatForever(autoreverses: true)
                        ) {
                            iconBounce = -5
                        }
                    }

                Spacer()

                Text(task.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(task.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
        }
        .frame(height: 170)
        .scaleEffect(hovered ? 0.97 : 1)
        .shadow(color: task.primaryColor.opacity(0.4), radius: hovered ? 8 : 20, y: hovered ? 4 : 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hovered)
        ._onButtonGesture(pressing: { hovered = $0 }, perform: {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                onTap()
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        })
    }
}

// Helper to get allCases from enum inside TaskCard
private extension MLTask {
    var allCases: [MLTask] { MLTask.allCases }
}

// MARK: - Preview

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            ForEach(MLTask.allCases) { task in
                TaskCard(task: task)
            }
        }
        .padding()
    }
    .background(.black)
}
