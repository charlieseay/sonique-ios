import Foundation
import AVFoundation

/// Synthesized audio cues. A rising (crescendo) chime when the assistant is ready to
/// use, and a falling (decrescendo) chime when it goes to sleep — cueing the user that
/// they'll need the wake word to start again.
@MainActor
final class SoundCues {
    static let shared = SoundCues()

    enum Cue {
        case ready
        case sleep
        case thinking
        case tokenReceived
    }

    private var player: AVAudioPlayer?
    private init() {}

    func play(_ cue: Cue) {
        switch cue {
        case .ready: playReady()
        case .sleep: playSleep()
        case .thinking: playThinking()
        case .tokenReceived: playTokenReceived()
        }
    }

    /// Ready: two soft ascending notes — a gentle, quiet rise.
    private func playReady() {
        let notes: [(freq: Double, start: Double, dur: Double)] = [
            (587.33, 0.00, 0.16),   // D5
            (880.00, 0.10, 0.26)    // A5 — soft perfect fifth up
        ]
        playWav(buildChime(notes: notes, totalDuration: 0.40, crescendo: true))
    }

    /// Sleep: two soft descending notes — a quiet settle.
    private func playSleep() {
        let notes: [(freq: Double, start: Double, dur: Double)] = [
            (880.00, 0.00, 0.16),   // A5
            (587.33, 0.10, 0.30)    // D5 — gentle fall
        ]
        playWav(buildChime(notes: notes, totalDuration: 0.44, crescendo: false))
    }

    /// Thinking: single soft note — acknowledges request received
    private func playThinking() {
        let notes: [(freq: Double, start: Double, dur: Double)] = [
            (659.25, 0.00, 0.12)    // E5 — brief acknowledgment
        ]
        playWav(buildChime(notes: notes, totalDuration: 0.15, crescendo: false), volume: 0.18)
    }

    /// Token received: single subtle windchime note
    private func playTokenReceived() {
        let notes: [(freq: Double, start: Double, dur: Double)] = [
            (1046.50, 0.00, 0.08)   // C6 — brief high chime
        ]
        playWav(buildChime(notes: notes, totalDuration: 0.10, crescendo: false), volume: 0.12)
    }

    // MARK: - Synthesis

    private func playWav(_ data: Data, volume: Float = 0.28) {
        do {
            let p = try AVAudioPlayer(data: data)
            p.volume = volume   // subtle — soft background cue, not an alert
            player = p
            p.play()
        } catch {
            // non-fatal — cues are optional polish
        }
    }

    /// Build a small WAV (24kHz mono 16-bit) mixing sine notes with an overall
    /// crescendo or decrescendo envelope.
    private func buildChime(notes: [(freq: Double, start: Double, dur: Double)],
                            totalDuration: Double, crescendo: Bool) -> Data {
        let sampleRate = 24000.0
        let total = Int(totalDuration * sampleRate)
        var samples = [Float](repeating: 0, count: total)

        for note in notes {
            let startIdx = Int(note.start * sampleRate)
            let count = Int(note.dur * sampleRate)
            for i in 0..<count {
                let idx = startIdx + i
                guard idx < total else { break }
                let t = Double(i) / sampleRate
                // Soft attack/decay envelope (sin^2 = gentler than sin, no clicks).
                let e = sin(Double.pi * Double(i) / Double(count))
                let noteEnv = e * e
                let s = sin(2 * Double.pi * note.freq * t) * noteEnv
                samples[idx] += Float(s) * 0.35
            }
        }

        // Overall crescendo (0→1) or decrescendo (1→0) envelope.
        for i in 0..<total {
            let p = Double(i) / Double(total)
            let env = crescendo ? p : (1.0 - p)
            samples[i] *= Float(0.4 + 0.6 * env)
        }

        return wavData(fromFloat: samples, sampleRate: Int(sampleRate))
    }

    private func wavData(fromFloat samples: [Float], sampleRate: Int) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            var i16 = Int16(clamped * 32767).littleEndian
            pcm.append(Data(bytes: &i16, count: 2))
        }
        let channels = 1, bits = 16
        let byteRate = sampleRate * channels * bits / 8
        let blockAlign = channels * bits / 8
        var h = Data()
        func str(_ s: String) { h.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bits))
        str("data"); u32(UInt32(pcm.count))
        var out = h; out.append(pcm); return out
    }
}
