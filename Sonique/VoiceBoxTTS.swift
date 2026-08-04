import Foundation
import AVFoundation
import CryptoKit

/// VoiceBox TTS via SoniqueBar
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
            await sendFeedback(type: "error", message: "fetchPCM called with empty text", metadata: [:])
            return nil
        }

        FileTracer.log("[voicebox] fetching TTS for: '\(text.prefix(50))'")

        // Report request start
        let requestStartTime = Date()
        await sendFeedback(type: "performance", message: "TTS request sent", metadata: [
            "text_length": text.count,
            "provider": "Fish"
        ])

        // Call SoniqueBar /synthesize/fish endpoint (Fish Speech TTS)
        guard let url = URL(string: "http://\(soniqueBarHost):8890/synthesize/fish") else {
            FileTracer.log("[voicebox] Invalid URL")
            await sendFeedback(type: "error", message: "Invalid Fish TTS URL", metadata: ["host": soniqueBarHost])
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
            "voice": "default"  // Fish TTS uses "default" voice
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            FileTracer.log("[voicebox] Failed to serialize JSON")
            await sendFeedback(type: "error", message: "Failed to serialize VoiceBox TTS JSON", metadata: ["text_length": text.count])
            return nil
        }

        request.httpBody = jsonData
        request.timeoutInterval = 30

        // Add request signature for integrity check
        if let authToken = authToken, !authToken.isEmpty,
           let signature = signRequest(jsonData, with: authToken) {
            request.setValue(signature, forHTTPHeaderField: "X-Request-Signature")
        }

        // Track TTS latency for feedback
        let startTime = Date()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let responseReceivedTime = Date()

            guard let httpResponse = response as? HTTPURLResponse else {
                FileTracer.log("[voicebox] Invalid response type")
                await sendFeedback(type: "error", message: "Invalid HTTP response type from VoiceBox", metadata: ["latency_ms": latencyMs])
                return nil
            }

            FileTracer.log("[voicebox] HTTP \(httpResponse.statusCode), received \(data.count) bytes")

            guard httpResponse.statusCode == 200 else {
                if let errorString = String(data: data, encoding: .utf8) {
                    FileTracer.log("[voicebox] Server error: \(errorString)")
                    await sendFeedback(type: "error", message: "VoiceBox TTS server error", metadata: [
                        "status_code": httpResponse.statusCode,
                        "error": errorString.prefix(100)
                    ])
                }
                return nil
            }

            // Report response received
            await sendFeedback(type: "performance", message: "TTS response received", metadata: [
                "response_size": data.count,
                "latency_ms": latencyMs
            ])

            // Check Content-Type header
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            FileTracer.log("[voicebox] Content-Type: \(contentType)")

            if contentType.contains("audio/pcm") {
                // Already PCM - return directly
                FileTracer.log("[voicebox] Received \(data.count) bytes PCM in \(latencyMs)ms")

                // Report successful PCM receipt
                await sendFeedback(type: "performance", message: "PCM data received successfully", metadata: [
                    "pcm_size": data.count,
                    "latency_ms": latencyMs,
                    "text_length": text.count
                ])

                return data
            } else {
                FileTracer.log("[voicebox] Unexpected Content-Type: \(contentType)")
                await sendFeedback(type: "error", message: "VoiceBox TTS unexpected content type", metadata: [
                    "content_type": contentType,
                    "expected": "audio/pcm"
                ])
                return nil
            }
        } catch {
            FileTracer.log("[voicebox] Request failed: \(error.localizedDescription)")

            // Report TTS failure
            await sendFeedback(type: "error", message: "VoiceBox TTS request failed: \(error.localizedDescription)", metadata: [
                "text_length": text.count,
                "error": error.localizedDescription.prefix(100)
            ])

            return nil
        }
    }

    func stop() {
        // VoiceBox synthesis is synchronous on SoniqueBar side
        // iOS playback stop is handled by VoiceSession
    }

    private func signRequest(_ body: Data, with authToken: String) -> String? {
        guard let keyData = authToken.data(using: .utf8) else { return nil }
        let signature = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: keyData))
        return Data(signature).base64EncodedString()
    }

    // MARK: - Feedback Reporting

    /// Send feedback to SoniqueBar for diagnostics
    private func sendFeedback(type: String, message: String, metadata: [String: Any]) async {
        let serverURL = await MainActor.run { UserDefaults.standard.string(forKey: "serverURL") ?? Config.defaultLANURL }
        let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken ?? "5FA5EE09-442D-4969-B091-9AC331E1C39C" }

        guard let url = URL(string: "\(serverURL)/feedback") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let payload: [String: Any] = [
            "type": type,
            "message": message,
            "metadata": metadata
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                FileTracer.log("[feedback] Sent: [\(type)] \(message)")
            }
        } catch {
            // Silent failure - don't want feedback reporting to interfere
            FileTracer.log("[feedback] Failed to send: \(error.localizedDescription)")
        }
    }
}
