import Foundation
import AVFoundation

/// Orchestrates the full voice assistant loop:
/// 1. User speaks → mic
/// 2. Audio → ElevenLabs WebSocket → STT transcript
/// 3. Transcript → SoniqueBar HTTP API → command execution
/// 4. Response text → ElevenLabs → TTS audio
/// 5. TTS audio → speaker playback
@MainActor
class VoiceLoop: ObservableObject {
    @Published var isActive = false
    @Published var lastTranscript = ""
    @Published var lastResponse = ""
    @Published var error: String?
    @Published var isInitializing = false

    private var elevenLabs: ElevenLabsClient?
    private var isProcessing = false

    init() {
        // Monitor transcript changes
        Task {
            await observeTranscripts()
        }
    }

    // MARK: - Control

    func start() async {
        guard !isActive else { return }

        // Fetch API key and initialize client if needed
        if elevenLabs == nil {
            isInitializing = true

            do {
                let apiKey = try await Config.getAPIKey()
                elevenLabs = ElevenLabsClient(apiKey: apiKey)
                isInitializing = false
            } catch {
                self.error = "Failed to fetch API key: \(error.localizedDescription)"
                isInitializing = false
                return
            }
        }

        guard let client = elevenLabs else { return }

        client.connect()
        client.startListening()
        isActive = true

        print("[VoiceLoop] Started")
    }

    func stop() {
        guard isActive else { return }
        guard let client = elevenLabs else { return }

        client.stopListening()
        client.disconnect()
        isActive = false

        print("[VoiceLoop] Stopped")
    }

    // MARK: - Voice Loop Pipeline

    private func observeTranscripts() async {
        // Watch for new transcripts from ElevenLabs
        for await _ in NotificationCenter.default.notifications(named: .elevenLabsTranscript) {
            guard let client = elevenLabs else { continue }

            let transcript = client.lastTranscript
            guard !transcript.isEmpty else { continue }
            guard !isProcessing else { continue }

            isProcessing = true
            lastTranscript = transcript

            print("[VoiceLoop] Transcript: \(transcript)")

            // Send to CommandServer
            do {
                let response = try await HTTPClient.sendCommand(transcript)
                lastResponse = response

                print("[VoiceLoop] Response: \(response)")

                // Send response back to ElevenLabs for TTS
                client.sendText(response)

            } catch {
                self.error = error.localizedDescription
                print("[VoiceLoop] Error: \(error)")
            }

            isProcessing = false
        }
    }

    // MARK: - Health Check

    func checkConnection() async -> Bool {
        do {
            return try await HTTPClient.healthCheck()
        } catch {
            self.error = "Cannot reach SoniqueBar: \(error.localizedDescription)"
            return false
        }
    }
}

extension Notification.Name {
    static let elevenLabsTranscript = Notification.Name("elevenLabsTranscript")
}
