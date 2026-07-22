import Foundation
import AVFoundation

/// Direct ElevenLabs TTS provider - connects directly to ElevenLabs websocket
/// Fetches credentials from SoniqueBar /config endpoint, then streams audio directly
/// Enables real barge-in by owning the websocket connection
@MainActor
class ElevenLabsDirectTTS: NSObject, TTSProvider {
    private let soniqueBarHost: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var audioQueue: [Data] = []
    private var isPlaying = false

    // Configuration from /config endpoint
    private var apiKey: String?
    private var voiceId: String?
    private var model: String?

    init(soniqueBarHost: String) {
        self.soniqueBarHost = soniqueBarHost
        super.init()
    }

    /// Fetch configuration from SoniqueBar before first TTS request
    private func fetchConfig() async -> Bool {
        guard let url = URL(string: "http://\(soniqueBarHost):8890/config") else {
            FileTracer.log("[elevenlabs] Invalid config URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        // Add bearer token authentication
        let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileTracer.log("[elevenlabs] Config fetch failed: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }

            let config = try JSONDecoder().decode(ConfigResponse.self, from: data)
            self.apiKey = config.elevenlabs.api_key
            self.voiceId = config.elevenlabs.voice_id
            self.model = config.elevenlabs.model

            FileTracer.log("[elevenlabs] ✓ Config loaded: voice=\(config.elevenlabs.voice_id)")
            return true

        } catch {
            FileTracer.log("[elevenlabs] Config parse error: \(error.localizedDescription)")
            return false
        }
    }

    func speak(_ text: String, completion: @escaping () -> Void) async {
        // Unused protocol method - VoiceLoop uses fetchPCM() only
        fatalError("ElevenLabsDirectTTS.speak() should not be called; use fetchPCM() instead")
    }

    func fetchPCM(_ text: String) async -> Data? {
        guard !text.isEmpty else {
            FileTracer.log("[elevenlabs] fetchPCM called with empty text")
            return nil
        }

        // Fetch config if not already loaded
        if apiKey == nil {
            guard await fetchConfig() else {
                FileTracer.log("[elevenlabs] Failed to fetch config")
                return nil
            }
        }

        guard let apiKey = apiKey, let voiceId = voiceId, let model = model else {
            FileTracer.log("[elevenlabs] Missing configuration")
            return nil
        }

        FileTracer.log("[elevenlabs] fetching TTS for: '\(text.prefix(50))'")

        // ElevenLabs text-to-speech endpoint (non-streaming for now)
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)") else {
            FileTracer.log("[elevenlabs] Invalid URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 30

        let payload: [String: Any] = [
            "text": text,
            "model_id": model,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            FileTracer.log("[elevenlabs] Failed to serialize payload")
            return nil
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileTracer.log("[elevenlabs] API error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            // ElevenLabs returns MP3 by default - convert to PCM
            FileTracer.log("[elevenlabs] received \(data.count) bytes MP3")
            return convertMP3ToPCM(data)

        } catch {
            FileTracer.log("[elevenlabs] fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func convertMP3ToPCM(_ mp3Data: Data) -> Data? {
        // Write MP3 to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")

        do {
            try mp3Data.write(to: tempURL)

            // Read as AVAudioFile
            let audioFile = try AVAudioFile(forReading: tempURL)
            let format = audioFile.processingFormat

            // Create buffer for entire file
            let frameCount = UInt32(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                FileTracer.log("[elevenlabs] Failed to create PCM buffer")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            try audioFile.read(into: buffer, frameCount: frameCount)

            // Convert to Data
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            let pcmData = Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))

            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)

            FileTracer.log("[elevenlabs] ✓ Converted MP3 to \(pcmData.count) bytes PCM")
            return pcmData

        } catch {
            FileTracer.log("[elevenlabs] MP3→PCM conversion failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    func stop() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        audioQueue.removeAll()
        FileTracer.log("[elevenlabs] Stopped")
    }
}

// MARK: - Config Response Models

private struct ConfigResponse: Codable {
    let elevenlabs: ElevenLabsConfig
    let kokoro: KokoroConfig
    let conversation: ConversationConfig
}

private struct ElevenLabsConfig: Codable {
    let api_key: String
    let voice_id: String
    let model: String
}

private struct KokoroConfig: Codable {
    let enabled: Bool
    let url: String
}

private struct ConversationConfig: Codable {
    let session_id: String
    let interface: String
}
