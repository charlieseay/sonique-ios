import SwiftUI

/// Visual feedback for Quinn's current state
/// Addresses Feature #5: Users need to know what Quinn is doing
struct StatusIndicatorView: View {
    let state: AssistantState
    let memoryEnabled: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Main status indicator
            stateIndicator
                .frame(width: 60, height: 60)

            // Memory mode chip
            if memoryEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10))
                    Text("Memory On")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(12)
            }
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .idle:
            // No indicator when idle
            EmptyView()

        case .listening:
            // Pulsing blue circle
            PulsingCircle(color: .blue)
                .accessibilityLabel("Listening")

        case .thinking:
            // Animated spinner
            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                    .scaleEffect(1.5)
                Text("Thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Thinking")

        case .speaking:
            // Voice waveform animation
            WaveformView()
                .accessibilityLabel("Speaking")
        }
    }
}

// MARK: - Assistant State

enum AssistantState {
    case idle
    case listening
    case thinking
    case speaking
}

// MARK: - Pulsing Circle

struct PulsingCircle: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .fill(color.opacity(0.3))
                .scaleEffect(isAnimating ? 1.4 : 1.0)
                .opacity(isAnimating ? 0.0 : 1.0)

            // Inner circle
            Circle()
                .fill(color)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
        }
        .onAppear {
            withAnimation(
                Animation
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    @State private var phase: CGFloat = 0

    private let barCount = 5
    private let barSpacing: CGFloat = 4
    private let barWidth: CGFloat = 3

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.green)
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(
                        Animation
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.1),
                        value: phase
                    )
            }
        }
        .onAppear {
            phase = 1
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 10
        let maxHeight: CGFloat = 40
        let animationOffset = sin(phase * .pi * 2 + Double(index) * 0.5)
        return baseHeight + (maxHeight - baseHeight) * CGFloat((animationOffset + 1) / 2)
    }
}

// MARK: - Preview

struct StatusIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            StatusIndicatorView(state: .idle, memoryEnabled: false)
            StatusIndicatorView(state: .listening, memoryEnabled: true)
            StatusIndicatorView(state: .thinking, memoryEnabled: true)
            StatusIndicatorView(state: .speaking, memoryEnabled: false)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
