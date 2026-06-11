import Foundation
import AVFoundation

@MainActor
class VoiceLoop: ObservableObject {
    @Published var isActive = false
    @Published var lastTranscript = ""
    @Published var lastResponse = ""
    @Published var partialResponse = ""
    @Published var error: String?
    @Published var isInitializing = false
    @Published var isProcessing = false
    @Published var isBargeInActive = false
    @Published var debugLog: [String] = []

    private(set) var whisperSTT: WhisperKitSTTService?
    private var ttsClient: ElevenLabsTTSClient?

    var speechRecognition: WhisperKitSTTService? { whisperSTT }

    var currentTranscript: String { whisperSTT?.transcript ?? "" }
    var callbackCount: Int { whisperSTT?.callbackCount ?? 0 }

    init() {
        Task { await observeTranscripts() }
    }

    // MARK: - Control

    func start() async {
        guard !isActive else { return }

        debugLog.append("Starting...")

        if whisperSTT == nil {
            isInitializing = true
            debugLog.append("Loading WhisperKit model...")

            let stt = WhisperKitSTTService()
            let hasPermission = await stt.requestPermission()
            guard hasPermission else {
                error = "Microphone permission denied"
                debugLog.append("ERROR: mic permission denied")
                isInitializing = false
                return
            }

            await stt.loadModel()
            guard stt.isModelLoaded else {
                error = stt.error ?? "WhisperKit model failed to load"
                debugLog.append("ERROR: model load failed")
                isInitializing = false
                return
            }

            whisperSTT = stt
            debugLog.append("WhisperKit ready")

            do {
                debugLog.append("Fetching TTS API key...")
                let apiKey = try await Config.getAPIKey()
                ttsClient = ElevenLabsTTSClient(apiKey: apiKey)
                debugLog.append("TTS ready")
            } catch {
                self.error = "TTS init failed: \(error.localizedDescription)"
                debugLog.append("ERROR: TTS - \(error.localizedDescription)")
                isInitializing = false
                return
            }

            isInitializing = false
        }

        guard let stt = whisperSTT else {
            debugLog.append("ERROR: no STT service")
            return
        }

        do {
            debugLog.append("Starting listening...")
            try stt.startListening()
            isActive = true
            debugLog.append("STT STARTED ✓")
        } catch {
            self.error = "Start failed: \(error.localizedDescription)"
            debugLog.append("ERROR: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isActive else { return }
        whisperSTT?.stopListening()
        ttsClient?.stop()
        isActive = false
        isProcessing = false
    }

    // MARK: - Voice Loop Pipeline

    private func observeTranscripts() async {
        for await notification in NotificationCenter.default.notifications(named: .speechTranscriptComplete) {
            guard let transcript = notification.userInfo?["transcript"] as? String,
                  !transcript.isEmpty else { continue }

            // Barge-in: interrupt current response if processing
            if isProcessing {
                debugLog.append("[barge-in] '\(transcript)'")
                isBargeInActive = true
                ttsClient?.interrupt()
                try? await Task.sleep(nanoseconds: 100_000_000)
                isBargeInActive = false
                isProcessing = false
            }

            isProcessing = true
            lastTranscript = transcript
            partialResponse = ""
            debugLog.append("You: \(transcript)")

            do {
                try await processWithStreaming(transcript)
            } catch {
                self.error = error.localizedDescription
                debugLog.append("ERROR: \(error.localizedDescription)")
            }

            isProcessing = false
        }
    }

    private func processWithStreaming(_ transcript: String) async throws {
        var sentenceBuffer = ""
        var fullResponse = ""

        for try await chunk in HTTPClient.sendCommandStreaming(transcript) {
            if isBargeInActive { break }

            sentenceBuffer += chunk.text + " "
            fullResponse += chunk.text + " "
            partialResponse = fullResponse.trimmingCharacters(in: .whitespaces)

            let (sentences, remainder) = extractCompleteSentences(from: sentenceBuffer)
            sentenceBuffer = remainder

            for sentence in sentences {
                if isBargeInActive { break }
                ttsClient?.enqueueSentence(sentence)
            }
        }

        // Flush any remaining text
        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty && !isBargeInActive {
            ttsClient?.enqueueSentence(remaining)
            fullResponse += remaining
        }

        lastResponse = fullResponse.trimmingCharacters(in: .whitespaces)
        partialResponse = ""
    }

    private func extractCompleteSentences(from text: String) -> ([String], String) {
        var sentences: [String] = []
        var remainder = text
        let terminators = CharacterSet(charactersIn: ".!?…")

        while let range = remainder.rangeOfCharacter(from: terminators) {
            let afterTerminator = remainder.index(after: range.lowerBound)
            // Only split on terminator followed by space or end
            if afterTerminator == remainder.endIndex || remainder[afterTerminator] == " " {
                let sentence = String(remainder[...range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { sentences.append(sentence) }
                remainder = afterTerminator < remainder.endIndex
                    ? String(remainder[afterTerminator...]).trimmingCharacters(in: .init(charactersIn: " "))
                    : ""
            } else {
                break
            }
        }

        return (sentences, remainder)
    }

    // MARK: - Health Check

    func checkConnection() async -> Bool {
        do { return try await HTTPClient.healthCheck() }
        catch { self.error = "Cannot reach SoniqueBar: \(error.localizedDescription)"; return false }
    }
}
