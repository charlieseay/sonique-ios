import Foundation
import AVFoundation

/// TTS provider protocol - supports multiple backends
protocol TTSProvider {
    func speak(_ text: String, completion: @escaping () -> Void) async
    func fetchPCM(_ text: String) async -> Data?  // For providers that return PCM data
    func stop()
}

/// VoiceBox TTS via SoniqueBar HTTP endpoint - returns PCM data for VoiceSession playback
@MainActor
class VoiceBoxTTS: NSObject, TTSProvider {
    private let soniqueBarHost: String

    init(soniqueBarHost: String) {
        self.soniqueBarHost = soniqueBarHost
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) async {
        // Not used - VoiceLoop calls fetchPCM() instead
        completion()
    }

    func fetchPCM(_ text: String) async -> Data? {
        guard !text.isEmpty else {
            FileTracer.log("[voicebox] fetchPCM called with empty text")
            return nil
        }

        FileTracer.log("[voicebox] fetching TTS for: '\(text.prefix(50))'")

        // Call SoniqueBar /synthesize endpoint
        guard let url = URL(string: "http://\(soniqueBarHost):8890/synthesize") else {
            FileTracer.log("[voicebox] Invalid URL")
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

        let payload: [String: Any] = [
            "text": text,
            "provider": "voicebox",
            "voice": "default"
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileTracer.log("[voicebox] API error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            FileTracer.log("[voicebox] received \(data.count) bytes \(contentType)")

            // Convert audio to PCM - handles both MP3 and AIFF
            return convertAudioToPCM(data, contentType: contentType)

        } catch {
            FileTracer.log("[voicebox] fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func convertAudioToPCM(_ audioData: Data, contentType: String) -> Data? {
        // Determine file extension from content type
        let ext: String
        if contentType.contains("mpeg") || contentType.contains("mp3") {
            ext = "mp3"
        } else if contentType.contains("aiff") || contentType.contains("x-aiff") {
            ext = "aiff"
        } else {
            // Default to trying as audio file
            ext = "audio"
        }

        // Write audio to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".\(ext)")
        FileTracer.log("[voicebox] converting \(ext) to PCM")

        do {
            try audioData.write(to: tempURL)

            // Read as AVAudioFile
            let audioFile = try AVAudioFile(forReading: tempURL)
            let format = audioFile.processingFormat

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioFile.length)) else {
                FileTracer.log("[voicebox] Failed to create PCM buffer")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            try audioFile.read(into: buffer)

            // Convert to 16-bit PCM data
            let pcmData = bufferToPCMData(buffer)

            // Cleanup
            try? FileManager.default.removeItem(at: tempURL)

            FileTracer.log("[voicebox] converted to \(pcmData?.count ?? 0) bytes PCM")
            return pcmData

        } catch {
            FileTracer.log("[voicebox] AIFF conversion failed: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    private func bufferToPCMData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData else { return nil }

        let frameCount = Int(buffer.frameLength)
        let floatSamples = UnsafeBufferPointer(start: floatData[0], count: frameCount)

        // Convert float32 [-1.0, 1.0] to int16 [-32768, 32767]
        var int16Samples = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let floatValue = floatSamples[i]
            let scaledValue = floatValue * 32767.0
            int16Samples[i] = Int16(max(-32768, min(32767, scaledValue)))
        }

        return Data(bytes: int16Samples, count: frameCount * 2)
    }

    func stop() {
        // Not used - VoiceSession handles stopping
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

    func fetchPCM(_ text: String) async -> Data? {
        // ElevenLabs returns PCM directly, not AIFF
        guard !text.isEmpty else { return nil }

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2",
            "output_format": "pcm_24000",  // 24kHz PCM
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
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
