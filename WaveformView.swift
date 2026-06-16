import SwiftUI

/// Real-time waveform visualization driven by actual microphone amplitude.
/// Shows blue rings during listening, purple rings during processing.
struct WaveformView: View {
    let isListening: Bool
    let isProcessing: Bool
    let audioLevel: Float

    @State private var animationPhase: CGFloat = 0

    private var color: Color {
        isProcessing ? .purple : .blue
    }

    private var ringCount: Int {
        isProcessing ? 3 : 2
    }

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .frame(width: baseSize(for: index), height: baseSize(for: index))
                    .scaleEffect(scale(for: index))
                    .opacity(opacity(for: index))
            }
        }
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                animationPhase = 1
            }
        }
    }

    private func baseSize(for index: Int) -> CGFloat {
        88 + CGFloat(index * 30)
    }

    private func scale(for index: Int) -> CGFloat {
        if isListening && !isProcessing {
            // Listening: scale based on actual audio level
            let levelScale = 1.0 + (CGFloat(audioLevel) * 0.3)
            let phase = (animationPhase + CGFloat(index) * 0.3).truncatingRemainder(dividingBy: 1.0)
            return levelScale * (1.0 + phase * 0.15)
        } else {
            // Processing: smooth pulsing animation
            let phase = (animationPhase + CGFloat(index) * 0.3).truncatingRemainder(dividingBy: 1.0)
            return 1.0 + phase * 0.2
        }
    }

    private func opacity(for index: Int) -> Double {
        let phase = (animationPhase + CGFloat(index) * 0.3).truncatingRemainder(dividingBy: 1.0)
        return Double(1.0 - phase)
    }
}
