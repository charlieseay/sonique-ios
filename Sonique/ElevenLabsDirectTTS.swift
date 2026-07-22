import Foundation
import AVFoundation

/// ElevenLabs TTS via SoniqueBar - server-side synthesis
/// Replaces client-side MP3→PCM conversion (which caused static/slow audio)
/// Server handles ElevenLabs API call + returns clean MP3
@MainActor
class ElevenLabsDirectTTS: NSObject, TTSProvider {
    private let soniqueBarHost: String

    init(soniqueBarHost: String) {
        self.soniqueBarHost = soniqueBarHost
        super.init()
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

            // Check Content-Type - should be audio/mpeg (MP3)
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            FileTracer.log("[elevenlabs] Content-Type: \(contentType)")

            if contentType.contains("audio/mpeg") {
                // Server returned MP3 - convert to PCM for AVAudioEngine
                FileTracer.log("[elevenlabs] Converting MP3 to PCM...")
                return convertMP3ToPCM(data)
            } else {
                FileTracer.log("[elevenlabs] Unexpected Content-Type: \(contentType)")
                return nil
            }
        } catch {
            FileTracer.log("[elevenlabs] Request failed: \(error.localizedDescription)")
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
        // Server-side synthesis - nothing to stop
    }
}
