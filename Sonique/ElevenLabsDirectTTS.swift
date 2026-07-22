import Foundation
import AVFoundation

/// ElevenLabs TTS via SoniqueBar - server-side synthesis
/// Server returns MP3, iOS plays it directly via AVAudioPlayer (no conversion needed)
@MainActor
class ElevenLabsDirectTTS: NSObject, TTSProvider, AVAudioPlayerDelegate {
    private let soniqueBarHost: String
    private var audioPlayer: AVAudioPlayer?
    private var completion: (() -> Void)?

    init(soniqueBarHost: String) {
        self.soniqueBarHost = soniqueBarHost
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) async {
        // Store completion for delegate callback
        self.completion = completion

        guard let mp3Data = await fetchMP3(text) else {
            FileTracer.log("[elevenlabs] Failed to fetch MP3")
            completion()
            return
        }

        // Play MP3 directly with AVAudioPlayer
        do {
            audioPlayer = try AVAudioPlayer(data: mp3Data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            FileTracer.log("[elevenlabs] ✓ Playing MP3 (\(mp3Data.count) bytes)")
        } catch {
            FileTracer.log("[elevenlabs] AVAudioPlayer error: \(error.localizedDescription)")
            completion()
        }
    }

    func fetchPCM(_ text: String) async -> Data? {
        // VoiceLoop doesn't use this path for ElevenLabs
        // It uses the speak() method above instead
        return nil
    }

    private func fetchMP3(_ text: String) async -> Data? {
        guard !text.isEmpty else {
            FileTracer.log("[elevenlabs] fetchMP3 called with empty text")
            return nil
        }

        FileTracer.log("[elevenlabs] fetching TTS for: '\(text.prefix(50))'")

        // Call SoniqueBar /synthesize/elevenlabs endpoint
        guard let url = URL(string: "http://\(soniqueBarHost):8890/synthesize/elevenlabs") else {
            FileTracer.log("[elevenlabs] Invalid URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add bearer token authentication
        let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = ["text": text]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            FileTracer.log("[elevenlabs] Failed to serialize JSON")
            return nil
        }

        request.httpBody = jsonData
        request.timeoutInterval = 30

        let startTime = Date()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                FileTracer.log("[elevenlabs] Invalid response type")
                return nil
            }

            FileTracer.log("[elevenlabs] HTTP \(httpResponse.statusCode), received \(data.count) bytes, latency \(latencyMs)ms")

            guard httpResponse.statusCode == 200 else {
                if let errorString = String(data: data, encoding: .utf8) {
                    FileTracer.log("[elevenlabs] Server error: \(errorString)")
                }
                return nil
            }

            return data

        } catch {
            FileTracer.log("[elevenlabs] Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        completion?()
        completion = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        FileTracer.log("[elevenlabs] Playback finished (success: \(flag))")
        completion?()
        completion = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        FileTracer.log("[elevenlabs] Decode error: \(error?.localizedDescription ?? "unknown")")
        completion?()
        completion = nil
    }
}
