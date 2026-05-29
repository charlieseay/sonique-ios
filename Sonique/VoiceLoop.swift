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
    @Published var characterUsage = 0

    private let elevenLabs: ElevenLabsClient
    private var isProcessing = false

    init() {
        self.elevenLabs = ElevenLabsClient(apiKey: Config.elevenlabsAPIKey)

        // Monitor transcript changes
        Task {
            await observeTranscripts()
        }
    }

    // MARK: - Control

    func start() {
        guard !isActive else { return }

        elevenLabs.connect()
        elevenLabs.startListening()
        isActive = true

        print("[VoiceLoop] Started")
    }

    func stop() {
        guard isActive else { return }

        elevenLabs.stopListening()
        elevenLabs.disconnect()
        isActive = false

        print("[VoiceLoop] Stopped")
    }

    // MARK: - Voice Loop Pipeline

    private func observeTranscripts() async {
        // Watch for new transcripts from ElevenLabs
        for await _ in NotificationCenter.default.notifications(named: .elevenLabsTranscript) {
            guard let transcript = elevenLabs.lastTranscript, !transcript.isEmpty else { continue }
            guard !isProcessing else { continue }

            isProcessing = true
            lastTranscript = transcript

            // Track character usage (input)
            characterUsage += transcript.count

            print("[VoiceLoop] Transcript: \(transcript)")

            // Send to CommandServer
            do {
                let response = try await HTTPClient.sendCommand(transcript)
                lastResponse = response

                // Track character usage (output)
                characterUsage += response.count

                print("[VoiceLoop] Response: \(response)")

                // Send response back to ElevenLabs for TTS
                elevenLabs.sendText(response)

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
