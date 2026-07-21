import Foundation
import AVFoundation
import CoreMedia
import Combine
import CryptoKit

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
        // Unused protocol method - VoiceLoop uses fetchPCM() only
        fatalError("VoiceBoxTTS.speak() should not be called; use fetchPCM() instead")
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
        request.timeoutInterval = 30  // ElevenLabs API can take 5-15s

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

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            FileTracer.log("[voicebox] Failed to serialize payload")
            return nil
        }
        request.httpBody = body

        // Add request signature for integrity check
        if let authToken = authToken, !authToken.isEmpty,
           let signature = signRequest(body, with: authToken) {
            request.setValue(signature, forHTTPHeaderField: "X-Request-Signature")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                FileTracer.log("[voicebox] API error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }

            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            FileTracer.log("[voicebox] received \(data.count) bytes \(contentType)")

            // Server now returns PCM directly - no conversion needed!
            if contentType.contains("audio/pcm") {
                FileTracer.log("[voicebox] ✓ Received PCM directly from server (\(data.count) bytes)")
                return data
            }

            // Legacy fallback: convert MP3/AIFF to PCM if server still returns it
            return convertAudioToPCM(data, contentType: contentType)

        } catch {
            FileTracer.log("[voicebox] fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func convertAudioToPCM(_ audioData: Data, contentType: String) -> Data? {
        FileTracer.log("[voicebox] Converting \(audioData.count) bytes (\(contentType)) to PCM")

        // For MP3: use AVAudioFile instead of AVAssetReader (better MP3 support)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")

        do {
            try audioData.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // Load MP3 file
            let audioFile = try AVAudioFile(forReading: tempURL)
            let format = audioFile.processingFormat

            FileTracer.log("[voicebox] Source: \(format.sampleRate)Hz, \(format.channelCount)ch")

            // Create target format: 24kHz mono int16
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 24000,
                channels: 1,
                interleaved: true
            ) else {
                FileTracer.log("[voicebox] ❌ Failed to create target format")
                return nil
            }

            // Read entire file into buffer
            let frameCapacity = AVAudioFrameCount(audioFile.length)
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                FileTracer.log("[voicebox] ❌ Failed to create source buffer")
                return nil
            }

            try audioFile.read(into: sourceBuffer)
            sourceBuffer.frameLength = frameCapacity

            // Convert to target format
            guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
                FileTracer.log("[voicebox] ❌ Failed to create converter")
                return nil
            }

            let ratio = targetFormat.sampleRate / format.sampleRate
            let targetFrameCount = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio)

            guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
                FileTracer.log("[voicebox] ❌ Failed to create target buffer")
                return nil
            }

            var error: NSError?
            let status = converter.convert(to: targetBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            guard status != .error else {
                FileTracer.log("[voicebox] ❌ Conversion error: \(error?.localizedDescription ?? "unknown")")
                return nil
            }

            targetBuffer.frameLength = targetFrameCount

            // Extract PCM data
            guard let pcmData = bufferToPCMData(targetBuffer) else {
                FileTracer.log("[voicebox] ❌ Failed to extract PCM data")
                return nil
            }

            FileTracer.log("[voicebox] ✓✓✓ Converted to \(pcmData.count) bytes PCM @ 24kHz")
            return pcmData

        } catch {
            FileTracer.log("[voicebox] ❌ Conversion failed: \(error)")
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

    private func signRequest(_ body: Data, with authToken: String) -> String? {
        guard let keyData = authToken.data(using: .utf8) else { return nil }
        let signature = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: keyData))
        return Data(signature).base64EncodedString()
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
