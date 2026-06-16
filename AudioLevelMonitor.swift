import Foundation
import AVFoundation

/// Real-time audio level monitor using Apple's AVAudioEngine installTap API.
/// Calculates RMS amplitude from microphone input for waveform visualization.
@MainActor
class AudioLevelMonitor: ObservableObject {
    @Published var currentLevel: Float = 0.0

    private let engine: AVAudioEngine
    private let smoothingFactor: Float = 0.3

    init(engine: AVAudioEngine) {
        self.engine = engine
    }

    /// Start monitoring audio levels by installing a tap on the input node.
    func startMonitoring() {
        let inputNode = engine.inputNode
        let bus: AVAudioNodeBus = 0
        let format = inputNode.outputFormat(forBus: bus)

        // Remove any existing tap
        inputNode.removeTap(onBus: bus)

        // Install tap with default buffer size (1024 frames)
        inputNode.installTap(onBus: bus, bufferSize: 0, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateRMS(buffer)

            Task { @MainActor in
                // Smooth the level changes for better visual appearance
                self.currentLevel = self.currentLevel * (1 - self.smoothingFactor) + level * self.smoothingFactor
            }
        }
    }

    /// Stop monitoring by removing the tap.
    func stopMonitoring() {
        engine.inputNode.removeTap(onBus: 0)
        Task { @MainActor in
            currentLevel = 0.0
        }
    }

    /// Calculate RMS (Root Mean Square) amplitude from audio buffer.
    /// Apple docs: floatChannelData contains normalized samples (-1.0 to 1.0).
    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return 0 }

        var sum: Float = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sum += sample * sample
            }
        }

        let rms = sqrt(sum / Float(frameLength * channelCount))

        // Clamp to 0.0-1.0 range
        return max(0.0, min(1.0, rms * 10)) // Amplify for better visualization
    }
}
