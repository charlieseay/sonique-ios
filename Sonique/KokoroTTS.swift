import Foundation
import AVFoundation

/// Kokoro TTS via SoniqueBar - native Swift on-device synthesis
@MainActor
class KokoroTTS: NSObject, TTSProvider {
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
            FileTracer.log("[kokoro] fetchPCM called with empty text")
            return nil
        }

        FileTracer.log("[kokoro] fetching TTS for: '\(text.prefix(50))'")

        // Call SoniqueBar /synthesize/kokoro endpoint
        guard let url = URL(string: "http://\(soniqueBarHost):8890/synthesize/kokoro") else {
            FileTracer.log("[kokoro] Invalid URL")
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
            "voice": "af_jessica"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            FileTracer.log("[kokoro] Failed to serialize JSON")
            return nil
        }

        request.httpBody = jsonData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                FileTracer.log("[kokoro] Invalid response type")
                return nil
            }

            FileTracer.log("[kokoro] HTTP \(httpResponse.statusCode), received \(data.count) bytes")

            guard httpResponse.statusCode == 200 else {
                if let errorString = String(data: data, encoding: .utf8) {
                    FileTracer.log("[kokoro] Server error: \(errorString)")
                }
                return nil
            }

            // Check Content-Type header
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            FileTracer.log("[kokoro] Content-Type: \(contentType)")

            if contentType.contains("audio/pcm") {
                // Already PCM - return directly
                FileTracer.log("[kokoro] ✓ Received \(data.count) bytes PCM")
                return data
            } else {
                FileTracer.log("[kokoro] ⚠️ Unexpected Content-Type: \(contentType)")
                return nil
            }
        } catch {
            FileTracer.log("[kokoro] Request failed: \(error.localizedDescription)")
            return nil
        }
    }

    func stop() {
        // Kokoro synthesis is synchronous on SoniqueBar side
        // iOS playback stop is handled by VoiceSession
    }
}
