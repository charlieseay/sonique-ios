import Foundation
import AVFoundation

/// Orchestrates the full voice assistant loop:
/// 1. User speaks → Apple Speech Recognition → transcript
/// 2. Transcript → SoniqueBar HTTP API → command execution
/// 3. Response text → ElevenLabs TTS → audio playback
@MainActor
class VoiceLoop: ObservableObject {
    @Published var isActive = false
    @Published var lastTranscript = ""
    @Published var lastResponse = ""
    @Published var error: String?
    @Published var isInitializing = false
    @Published var isProcessing = false

    private var speechRecognition: SpeechRecognitionService?
    private var ttsClient: ElevenLabsTTSClient?

    init() {
        // Monitor transcript changes
        Task {
            await observeTranscripts()
        }
    }

    // MARK: - Control

    func start() async {
        guard !isActive else { return }

        // Initialize services if needed
        if speechRecognition == nil {
            isInitializing = true

            // Request permissions
            let sttService = SpeechRecognitionService()
            let hasPermission = await sttService.requestPermission()

            guard hasPermission else {
                self.error = "Microphone or speech recognition permission denied"
                isInitializing = false
                return
            }

            speechRecognition = sttService

            // Initialize TTS client
            do {
                let apiKey = try await Config.getAPIKey()
                ttsClient = ElevenLabsTTSClient(apiKey: apiKey)
            } catch {
                self.error = "Failed to initialize TTS: \(error.localizedDescription)"
                isInitializing = false
                return
            }

            isInitializing = false
        }

        guard let stt = speechRecognition else { return }

        // Start listening
        do {
            try stt.startListening()
            isActive = true
            print("[VoiceLoop] Started")
        } catch {
            self.error = "Failed to start listening: \(error.localizedDescription)"
        }
    }

    func stop() {
        guard isActive else { return }

        speechRecognition?.stopListening()
        ttsClient?.stop()
        isActive = false

        print("[VoiceLoop] Stopped")
    }

    // MARK: - Voice Loop Pipeline

    private func observeTranscripts() async {
        // Watch for completed transcripts
        for await notification in NotificationCenter.default.notifications(named: .speechTranscriptComplete) {
            guard let transcript = notification.userInfo?["transcript"] as? String else { continue }
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

                // Speak response via ElevenLabs TTS
                if let tts = ttsClient {
                    try await tts.speak(response, voice: Config.selectedVoice)
                }

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
