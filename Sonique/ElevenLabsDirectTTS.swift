import Foundation
import AVFoundation

/// ElevenLabs TTS via SoniqueBar - server-side synthesis
/// Server returns MP3, iOS converts to Int16 24kHz mono PCM for VoiceSession
@MainActor
class ElevenLabsDirectTTS: NSObject, TTSProvider {
    private let soniqueBarHost: String

    init(soniqueBarHost: String) {
        self.soniqueBarHost = soniqueBarHost
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) async {
        // Unused - VoiceLoop uses fetchPCM()
        fatalError("ElevenLabsDirectTTS.speak() should not be called; use fetchPCM() instead")
    }

    func fetchPCM(_ text: String) async -> Data? {
        guard !text.isEmpty else {
            FileTracer.log("[elevenlabs] fetchPCM called with empty text")
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

        // Get selected voice ID from preferences
        let prefs = await MainActor.run { SoniqueBrain.shared.loadPreferences() }
        let voiceId = prefs.selectedVoiceID ?? "EXAVITQu4vr4xnSDxMaL" // Default voice

        let payload: [String: Any] = ["text": text, "voice_id": voiceId]

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

            // Convert MP3 to Int16 24kHz mono PCM (VoiceSession format)
            return convertMP3ToPCM(data)

        } catch {
            FileTracer.log("[elevenlabs] Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func convertMP3ToPCM(_ mp3Data: Data) -> Data? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")

        do {
            try mp3Data.write(to: tempURL)

            // Read MP3 file
            let audioFile = try AVAudioFile(forReading: tempURL)
            let sourceFormat = audioFile.processingFormat

            FileTracer.log("[elevenlabs] Source: \(sourceFormat.sampleRate)Hz, \(sourceFormat.channelCount)ch, \(sourceFormat.commonFormat.rawValue)")

            // Target format: Int16, 24kHz, mono (matches VoiceSession playerFormat)
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                   sampleRate: 24000,
                                                   channels: 1,
                                                   interleaved: false) else {
                FileTracer.log("[elevenlabs] Failed to create target format")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            // Create converter
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                FileTracer.log("[elevenlabs] Failed to create converter")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            // Read entire source file
            let frameCount = UInt32(audioFile.length)
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
                FileTracer.log("[elevenlabs] Failed to create source buffer")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            try audioFile.read(into: sourceBuffer, frameCount: frameCount)
            sourceBuffer.frameLength = frameCount

            // Calculate output frame count (resampling)
            let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
            let outputFrameCount = UInt32(Double(frameCount) * ratio)

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
                FileTracer.log("[elevenlabs] Failed to create output buffer")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            // Convert
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            if let error = error {
                FileTracer.log("[elevenlabs] Conversion error: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            // Extract Int16 data
            guard let channelData = outputBuffer.int16ChannelData else {
                FileTracer.log("[elevenlabs] No Int16 channel data")
                try? FileManager.default.removeItem(at: tempURL)
                return nil
            }

            let frameLength = Int(outputBuffer.frameLength)
            let pcmData = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Int16>.size)

            try? FileManager.default.removeItem(at: tempURL)

            FileTracer.log("[elevenlabs] ✓ Converted to \(pcmData.count) bytes Int16 24kHz mono PCM")
            return pcmData

        } catch {
            FileTracer.log("[elevenlabs] MP3→PCM conversion failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    func stop() {
        // Server-side synthesis - nothing to stop
    }
}
