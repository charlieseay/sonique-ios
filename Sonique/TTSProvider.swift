import Foundation
import AVFoundation

/// TTS provider protocol - supports multiple backends
protocol TTSProvider {
    func speak(_ text: String, completion: @escaping () -> Void) async
    func stop()
}

/// VoiceBox TTS via SoniqueBar HTTP endpoint
@MainActor
class VoiceBoxTTS: NSObject, TTSProvider, AVAudioPlayerDelegate {
    private let soniqueBarHost: String
    private var audioPlayer: AVAudioPlayer?
    private var onComplete: (() -> Void)?

    init(soniqueBarHost: String) {
        self.soniqueBarHost = soniqueBarHost
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) async {
        guard !text.isEmpty else {
            completion()
            return
        }

        onComplete = completion

        // Don't reconfigure audio session - VoiceSession already set it up with Bluetooth support
        FileTracer.log("[voicebox] fetching TTS for: '\(text.prefix(50))'")

        // Call SoniqueBar /synthesize endpoint
        guard let url = URL(string: "http://\(soniqueBarHost):8890/synthesize") else {
            FileTracer.log("[voicebox] Invalid URL")
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "provider": "kokoro",
            "voice": "af_bella"  // Premium female voice
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileTracer.log("[voicebox] API error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                completion()
                return
            }

            // SoniqueBar returns WAV file - play it directly
            FileTracer.log("[voicebox] received \(data.count) bytes")

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

        } catch {
            FileTracer.log("[voicebox] fetch failed: \(error.localizedDescription)")
            completion()
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        onComplete?()
        onComplete = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            FileTracer.log("[voicebox] finished playing")
            onComplete?()
            onComplete = nil
        }
    }
}

/// ElevenLabs TTS via direct API
@MainActor
class ElevenLabsTTS: NSObject, TTSProvider, AVAudioPlayerDelegate {
    private let apiKey: String
    private let voiceID: String
    private var audioPlayer: AVAudioPlayer?
    private var onComplete: (() -> Void)?

    init(apiKey: String, voiceID: String = "cgSgspJ2msm6clMCkdW9") {
        self.apiKey = apiKey
        self.voiceID = voiceID
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) async {
        guard !text.isEmpty else {
            completion()
            return
        }

        onComplete = completion

        // Don't reconfigure audio session - VoiceSession already set it up with Bluetooth support
        FileTracer.log("[elevenlabs] fetching TTS for: '\(text.prefix(50))'")

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileTracer.log("[elevenlabs] API error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                completion()
                return
            }

            FileTracer.log("[elevenlabs] received \(data.count) bytes")

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

        } catch {
            FileTracer.log("[elevenlabs] fetch failed: \(error.localizedDescription)")
            completion()
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        onComplete?()
        onComplete = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            FileTracer.log("[elevenlabs] finished playing")
            onComplete?()
            onComplete = nil
        }
    }
}
