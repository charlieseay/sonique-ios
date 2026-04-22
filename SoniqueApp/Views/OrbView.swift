import SwiftUI

/// Central animated orb — the visual centerpiece of the voice UI.
/// Changes appearance based on session and agent state.
struct OrbView: View {
    let sessionState: SessionState
    let agentState: AgentState

    @State private var breathScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var pulse1: CGFloat = 1.0
    @State private var pulse2: CGFloat = 1.0
    @State private var glow: CGFloat = 0.3

    private var orbSize: CGFloat { 180 }

    var body: some View {
        ZStack {
            // Outer ripples (active listening)
            if sessionState.isActive && agentState == .listening {
                ForEach(0..<3) { i in
                    Circle()
                        .strokeBorder(Color.soniqueAccent.opacity(0.2 - Double(i) * 0.05), lineWidth: 1.5)
                        .frame(width: orbSize + CGFloat(i + 1) * 40,
                               height: orbSize + CGFloat(i + 1) * 40)
                        .scaleEffect(pulse1)
                        .animation(
                            .easeOut(duration: 1.6)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.4),
                            value: pulse1
                        )
                }
            }

            // Glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbGlowColor.opacity(glow), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: orbSize * 0.8
                    )
                )
                .frame(width: orbSize * 1.6, height: orbSize * 1.6)
                .blur(radius: 20)

            // Main orb body
            Circle()
                .fill(orbGradient)
                .frame(width: orbSize, height: orbSize)
                .scaleEffect(breathScale)
                .overlay(
                    // Connecting spinner ring
                    sessionState.isConnecting ? AnyView(
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(
                                LinearGradient(colors: [.soniqueAccent2, .clear], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(rotationAngle))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: rotationAngle)
                    ) : AnyView(EmptyView())
                )
                .shadow(color: orbGlowColor.opacity(0.4), radius: 20, x: 0, y: 0)

            // Speaking bars
            if sessionState.isActive && agentState == .speaking {
                AudioBarsView()
            }

            // State icon (idle or error)
            if sessionState == .idle {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [.soniqueAccent, .soniqueAccent2],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: .soniqueAccent.opacity(0.5), radius: 10)
            }

            if case .error = sessionState {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.soniqueOffline)
            }
        }
        .onAppear { startAnimations() }
        .onChange(of: sessionState) { startAnimations() }
        .onChange(of: agentState) { startAnimations() }
    }

    // MARK: - Computed style

    private var orbGradient: some ShapeStyle {
        switch sessionState {
        case .idle:
            return LinearGradient(
                colors: [Color(white: 0.14), Color(white: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .connecting, .disconnecting:
            return LinearGradient(
                colors: [Color.soniqueAccent.opacity(0.3), Color.soniqueAccent2.opacity(0.15)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .active:
            switch agentState {
            case .idle, .listening:
                return LinearGradient(
                    colors: [Color.soniqueAccent.opacity(0.45), Color.soniqueAccent2.opacity(0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            case .thinking:
                return LinearGradient(
                    colors: [Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.45), Color.soniqueAccent.opacity(0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            case .speaking:
                return LinearGradient(
                    colors: [Color.soniqueAccent2.opacity(0.55), Color.soniqueAccent.opacity(0.40)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        case .error:
            return LinearGradient(
                colors: [Color.soniqueOffline.opacity(0.3), Color(white: 0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var orbGlowColor: Color {
        switch sessionState {
        case .active where agentState == .speaking: return .soniqueAccent2
        case .active:                               return .soniqueAccent
        case .connecting:                           return .soniqueAccent
        case .error:                                return .soniqueOffline
        default:                                    return .soniqueAccent
        }
    }

    // MARK: - Animations

    private func startAnimations() {
        switch sessionState {
        case .idle:
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                breathScale = 1.04
                glow = 0.25
            }
        case .connecting:
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                breathScale = 0.97
                glow = 0.4
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        case .active:
            switch agentState {
            case .idle, .listening:
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    breathScale = 1.06
                    glow = 0.5
                    pulse1 = 1.3
                }
            case .thinking:
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    breathScale = 1.02
                    glow = 0.45
                }
            case .speaking:
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    breathScale = 1.08
                    glow = 0.65
                }
            }
        case .error, .disconnecting:
            breathScale = 1.0
            glow = 0.15
        }
    }
}

// MARK: - Audio bars (agent speaking)

private struct AudioBarsView: View {
    @State private var levels: [CGFloat] = Array(repeating: 0.3, count: 5)

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.soniqueAccent2.opacity(0.85))
                    .frame(width: 4, height: 28 * levels[i])
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.3...0.6))
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.1),
                        value: levels[i]
                    )
            }
        }
        .onAppear {
            for i in 0..<5 {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 0.3...0.6))
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.1)
                ) {
                    levels[i] = CGFloat.random(in: 0.4...1.0)
                }
            }
        }
    }
}
