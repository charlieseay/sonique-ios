import Foundation
import AVFoundation

/// Simple on-device TTS using AVSpeechSynthesizer.speak() (the correct API)
@MainActor
class SimpleTTS: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var onComplete: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak text and call completion when done
    func speak(_ text: String, completion: @escaping () -> Void) {
        guard !text.isEmpty else {
            completion()
            return
        }

        FileTracer.log("[tts] speaking: '\(text.prefix(50))'")
        onComplete = completion

        let utterance = AVSpeechUtterance(string: text)

        // Use premium quality voices - find best female US English voice
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let premiumVoices = voices.filter { voice in
            voice.language == "en-US" &&
            voice.quality == .premium &&
            (voice.name.contains("Samantha") || voice.name.contains("Ava"))
        }

        utterance.voice = premiumVoices.first ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52  // Slightly faster than default for more natural conversation
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    /// Stop speaking immediately
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        onComplete?()
        onComplete = nil
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        FileTracer.log("[tts] finished speaking")
        onComplete?()
        onComplete = nil
    }

    // MARK: - Voice Selection Helper

    /// List all available premium voices for debugging
    static func listAvailableVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let usVoices = voices.filter { $0.language == "en-US" }
        FileTracer.log("[tts] Available US English voices:")
        for voice in usVoices {
            let quality = voice.quality == .premium ? "PREMIUM" : voice.quality == .enhanced ? "enhanced" : "default"
            FileTracer.log("[tts]   [\(quality)] \(voice.name) - \(voice.identifier)")
        }
    }
}
