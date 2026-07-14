import Foundation
import AVFoundation

/// On-device TTS using AVSpeechSynthesizer (free, offline)
@MainActor
class TTSClient: ObservableObject {
    enum Provider: String, Codable {
        case elevenlabs
        case kokoro

        var displayName: String {
            switch self {
            case .elevenlabs: return "ElevenLabs"
            case .kokoro: return "Kokoro (Local)"
            }
        }
    }

    private let elevenLabsAPIKey: String
    private let soniqueBarHost: String

    @Published var provider: Provider = .elevenlabs

    init(elevenLabsAPIKey: String, soniqueBarHost: String) {
        self.elevenLabsAPIKey = elevenLabsAPIKey
        self.soniqueBarHost = soniqueBarHost

        // Load saved provider preference
        if let saved = UserDefaults.standard.string(forKey: "tts_provider"),
           let savedProvider = Provider(rawValue: saved) {
            self.provider = savedProvider
        }
    }

    func setProvider(_ newProvider: Provider) {
        provider = newProvider
        UserDefaults.standard.set(newProvider.rawValue, forKey: "tts_provider")
    }

    /// Returns raw PCM (pcm_24000, 16-bit LE mono) for the given text, or nil on failure.
    func fetchPCM(_ text: String, voiceID: String) async -> Data? {
        guard !text.isEmpty else {
            FileTracer.log("[tts] fetchPCM called with empty text")
            return nil
        }

        FileTracer.log("[tts] fetchPCM called with: '\(text.prefix(50))'")
        // Use on-device AVSpeechSynthesizer (free, works offline)
        let result = await synthesizeOnDevice(text)
        FileTracer.log("[tts] synthesizeOnDevice returned: \(result?.count ?? 0) bytes")
        return result
    }

    // MARK: - ElevenLabs

    private func fetchFromElevenLabs(_ text: String, voiceID: String) async -> Data? {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=pcm_24000")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_turbo_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileTracer.log("[tts] ElevenLabs API error \(code)")
                return nil
            }
            FileTracer.log("[tts] fetched \(data.count) PCM bytes from ElevenLabs for '\(text.prefix(30))'")
            return data
        } catch {
            FileTracer.log("[tts] ElevenLabs fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - SoniqueBar Kokoro

    private func fetchFromSoniqueBar(_ text: String, voiceID: String) async -> Data? {
        // Map ElevenLabs voice IDs to Kokoro voices
        let kokoroVoice = mapToKokoroVoice(voiceID)

        guard let url = URL(string: "http://\(soniqueBarHost):8890/synthesize") else {
            FileTracer.log("[tts] Invalid SoniqueBar URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "provider": "kokoro",
            "voice": kokoroVoice
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileTracer.log("[tts] SoniqueBar API error \(code)")
                // Fallback to ElevenLabs on error
                FileTracer.log("[tts] Falling back to ElevenLabs...")
                return await fetchFromElevenLabs(text, voiceID: voiceID)
            }

            // SoniqueBar returns WAV file, need to extract PCM
            guard let pcm = extractPCMFromWAV(data) else {
                FileTracer.log("[tts] Failed to extract PCM from WAV, falling back to ElevenLabs")
                return await fetchFromElevenLabs(text, voiceID: voiceID)
            }

            FileTracer.log("[tts] fetched \(pcm.count) PCM bytes from Kokoro for '\(text.prefix(30))'")
            return pcm
        } catch {
            FileTracer.log("[tts] SoniqueBar fetch failed: \(error.localizedDescription), falling back to ElevenLabs")
            return await fetchFromElevenLabs(text, voiceID: voiceID)
        }
    }

    private func mapToKokoroVoice(_ elevenLabsVoiceID: String) -> String {
        // Map common ElevenLabs voices to Kokoro equivalents
        switch elevenLabsVoiceID {
        case "cgSgspJ2msm6clMCkdW9": // Jessica
            return "af_bella"
        default:
            return "af_bella" // Default to Bella (best quality)
        }
    }

    private func extractPCMFromWAV(_ wavData: Data) -> Data? {
        // WAV header is 44 bytes, followed by raw PCM data
        // Verify it's actually a WAV file
        guard wavData.count > 44 else { return nil }

        // Check RIFF header
        let riff = String(data: wavData.subdata(in: 0..<4), encoding: .ascii)
        guard riff == "RIFF" else { return nil }

        // Extract PCM data (skip 44-byte header)
        return wavData.subdata(in: 44..<wavData.count)
    }

    // MARK: - On-Device TTS (AVSpeechSynthesizer)

    // Keep synthesizer alive during synthesis
    private var activeSynthesizer: AVSpeechSynthesizer?

    private func synthesizeOnDevice(_ text: String) async -> Data? {
        FileTracer.log("[tts] synthesizeOnDevice START for '\(text.prefix(30))'")
        return await withCheckedContinuation { continuation in
            FileTracer.log("[tts] creating AVSpeechSynthesizer")
            let synthesizer = AVSpeechSynthesizer()
            self.activeSynthesizer = synthesizer  // Keep alive
            let utterance = AVSpeechUtterance(string: text)

            // Use natural US English voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5  // Natural speaking rate
            utterance.pitchMultiplier = 1.0

            var pcmData = Data()
            var isDone = false

            // AVSpeechSynthesizer.write() uses a simple buffer callback
            FileTracer.log("[tts] calling synthesizer.write()")
            let voice = synthesizer.write(utterance) { [weak self] buffer in
                guard let buffer = buffer else {
                    // nil buffer = end of synthesis
                    if !isDone {
                        isDone = true
                        self?.activeSynthesizer = nil
                        if pcmData.isEmpty {
                            FileTracer.log("[tts] synthesis complete but no data")
                            continuation.resume(returning: nil)
                        } else {
                            FileTracer.log("[tts] synthesized \(pcmData.count) PCM bytes on-device")
                            continuation.resume(returning: pcmData)
                        }
                    }
                    return
                }

                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    FileTracer.log("[tts] buffer is not AVAudioPCMBuffer")
                    return
                }

                FileTracer.log("[tts] got buffer: \(pcmBuffer.frameLength) frames, format=\(pcmBuffer.format)")

                // AVSpeechSynthesizer outputs float32, need to convert to int16
                if let floatData = pcmBuffer.floatChannelData {
                    let frameCount = Int(pcmBuffer.frameLength)
                    let floatSamples = UnsafeBufferPointer(start: floatData[0], count: frameCount)

                    // Convert float32 [-1.0, 1.0] to int16 [-32768, 32767]
                    var int16Samples = [Int16](repeating: 0, count: frameCount)
                    for i in 0..<frameCount {
                        let floatValue = floatSamples[i]
                        let scaledValue = floatValue * 32767.0
                        int16Samples[i] = Int16(max(-32768, min(32767, scaledValue)))
                    }

                    let data = Data(bytes: int16Samples, count: frameCount * 2)
                    pcmData.append(data)
                    FileTracer.log("[tts] converted \(frameCount) float32 samples to int16")
                } else {
                    FileTracer.log("[tts] no float channel data available")
                }
            }

            FileTracer.log("[tts] synthesizer.write() returned voice=\(voice != nil)")
            if voice == nil {
                FileTracer.log("[tts] on-device synthesis failed to start (voice=nil)")
                self.activeSynthesizer = nil
                continuation.resume(returning: nil)
            } else {
                FileTracer.log("[tts] synthesis started successfully, waiting for buffers...")
            }
        }
    }
}
