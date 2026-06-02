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
    @Published var debugLog: [String] = []

    private var speechRecognition: SpeechRecognitionService?
    private var ttsClient: ElevenLabsTTSClient?

    var currentTranscript: String {
        speechRecognition?.transcript ?? ""
    }

    init() {
        // Monitor transcript changes
        Task {
            await observeTranscripts()
        }
    }

    // MARK: - Control

    func start() async {
        guard !isActive else {
            print("[VoiceLoop] Already active, ignoring")
            return
        }

        debugLog.append("Starting...")

        // Initialize services if needed
        if speechRecognition == nil {
            isInitializing = true
            debugLog.append("Initializing services...")

            // Request permissions
            let sttService = SpeechRecognitionService()
            debugLog.append("Requesting permissions...")
            let hasPermission = await sttService.requestPermission()
            debugLog.append("Permission: \(hasPermission)")

            guard hasPermission else {
                self.error = "Permissions denied"
                debugLog.append("ERROR: Permissions denied")
                isInitializing = false
                return
            }

            speechRecognition = sttService

            // Initialize TTS client
            do {
                debugLog.append("Fetching API key...")
                let apiKey = try await Config.getAPIKey()
                debugLog.append("Initializing TTS...")
                ttsClient = ElevenLabsTTSClient(apiKey: apiKey)
                debugLog.append("TTS ready")
            } catch {
                self.error = "TTS init failed: \(error.localizedDescription)"
                debugLog.append("ERROR: TTS - \(error.localizedDescription)")
                isInitializing = false
                return
            }

            isInitializing = false
            debugLog.append("Services ready")
        }

        guard let stt = speechRecognition else {
            debugLog.append("ERROR: No STT service")
            return
        }

        // Start listening
        do {
            debugLog.append("Starting STT...")
            try stt.startListening()
            isActive = true
            debugLog.append("STT STARTED")
        } catch {
            self.error = "Start failed: \(error.localizedDescription)"
            debugLog.append("ERROR: \(error.localizedDescription)")
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
