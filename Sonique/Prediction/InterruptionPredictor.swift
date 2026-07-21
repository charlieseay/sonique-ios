import Foundation
import AVFoundation

/// Predicts whether detected speech is a real interruption vs a backchannel/acknowledgment.
/// Uses prosodic features, semantic patterns, and tunable threshold.
class InterruptionPredictor {
    /// Tunable threshold (0.0-1.0). Below this score = ignore, above = real interruption.
    /// Default 0.4 balances false positives (ignoring real commands) vs false negatives (interrupting on backchannels).
    private var threshold: Float = 0.4

    /// Backchannel patterns that should NOT interrupt (scored low)
    private let backchannelPatterns: Set<String> = [
        "mm-hmm", "mm hmm", "mhm", "uh-huh", "uh huh",
        "yeah", "yep", "yes", "okay", "ok", "right",
        "I see", "got it", "sure", "alright"
    ]

    /// Command patterns that SHOULD interrupt (scored high)
    private let commandPatterns: Set<String> = [
        "stop", "cancel", "wait", "hold on", "never mind",
        "actually", "correction", "change that", "no"
    ]

    /// Set interruption sensitivity (0.0 = very lenient, 1.0 = aggressive)
    func setThreshold(_ value: Float) {
        threshold = max(0.0, min(1.0, value))
    }

    /// Get current threshold
    func getThreshold() -> Float {
        return threshold
    }

    /// Predict interruption score for detected speech.
    /// Returns: 0.0 (definitely backchannel) to 1.0 (definitely interruption)
    func predict(
        transcript: String,
        duration: TimeInterval,
        energyLevel: Float?,
        pitchVariation: Float?,
        isQuinnSpeaking: Bool
    ) -> Float {
        var score: Float = 0.5  // Start neutral

        // 1. Pattern-based scoring (strongest signal)
        let lower = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Explicit commands → high score (likely real interruption)
        if commandPatterns.contains(where: { lower.contains($0) }) {
            score += 0.4
        }

        // Backchannel patterns → low score (likely acknowledgment)
        if backchannelPatterns.contains(lower) {
            score -= 0.4
        }

        // 2. Duration-based scoring
        // Short utterances (<0.5s) are usually backchannels unless they're commands
        if duration < 0.5 && !commandPatterns.contains(where: { lower.contains($0) }) {
            score -= 0.2
        }

        // Long utterances (>2s) are usually real interruptions
        if duration > 2.0 {
            score += 0.2
        }

        // 3. Energy-based scoring (if available)
        // Loud speech is more likely a real interruption
        if let energy = energyLevel {
            if energy > 0.7 {
                score += 0.1
            } else if energy < 0.3 {
                score -= 0.1
            }
        }

        // 4. Pitch variation scoring (if available)
        // High pitch variation suggests questioning/commanding (real interruption)
        // Flat pitch suggests acknowledgment (backchannel)
        if let pitch = pitchVariation {
            if pitch > 0.6 {
                score += 0.1
            } else if pitch < 0.3 {
                score -= 0.1
            }
        }

        // 5. Context-based scoring
        // If Quinn is speaking, default to higher score (user likely interrupting for a reason)
        if isQuinnSpeaking {
            score += 0.1
        }

        // Clamp final score to [0.0, 1.0]
        return max(0.0, min(1.0, score))
    }

    /// Convenience: should this transcript interrupt?
    func shouldInterrupt(
        transcript: String,
        duration: TimeInterval = 1.0,
        energyLevel: Float? = nil,
        pitchVariation: Float? = nil,
        isQuinnSpeaking: Bool
    ) -> Bool {
        let score = predict(
            transcript: transcript,
            duration: duration,
            energyLevel: energyLevel,
            pitchVariation: pitchVariation,
            isQuinnSpeaking: isQuinnSpeaking
        )
        return score >= threshold
    }
}

/// Audio feature extractor for prosodic analysis
class AudioFeatureExtractor {
    /// Extract energy level (loudness) from audio buffer
    /// Returns: 0.0 (quiet) to 1.0 (loud)
    static func extractEnergy(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        var sum: Float = 0.0
        let samples = channelData[0]
        for i in 0..<frameLength {
            sum += abs(samples[i])
        }

        let avgEnergy = sum / Float(frameLength)
        return min(avgEnergy * 10.0, 1.0)  // Scale to [0, 1]
    }

    /// Extract pitch variation (contour) from audio buffer
    /// Returns: 0.0 (flat) to 1.0 (highly varied)
    /// Note: This is a simplified approximation. Full pitch tracking requires FFT/autocorrelation.
    static func extractPitchVariation(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 10 else { return 0.0 }

        // Approximate pitch variation by measuring zero-crossing rate variation
        var zeroCrossings = [Int]()
        let windowSize = frameLength / 10
        let samples = channelData[0]

        for window in 0..<10 {
            var crossings = 0
            let start = window * windowSize
            let end = min(start + windowSize, frameLength - 1)

            for i in start..<end {
                if (samples[i] >= 0 && samples[i+1] < 0) || (samples[i] < 0 && samples[i+1] >= 0) {
                    crossings += 1
                }
            }
            zeroCrossings.append(crossings)
        }

        // Calculate coefficient of variation (std dev / mean)
        guard !zeroCrossings.isEmpty else { return 0.0 }
        let mean = Float(zeroCrossings.reduce(0, +)) / Float(zeroCrossings.count)
        guard mean > 0 else { return 0.0 }

        let variance = zeroCrossings.map { pow(Float($0) - mean, 2) }.reduce(0, +) / Float(zeroCrossings.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / mean

        return min(cv, 1.0)  // Clamp to [0, 1]
    }
}
