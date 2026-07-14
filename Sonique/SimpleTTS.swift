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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

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
}
