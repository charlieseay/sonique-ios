import Foundation
import Speech
import AVFoundation

/// Native iOS speech recognition using Apple Speech framework
@MainActor
class SpeechRecognitionService: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var error: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // MARK: - Permission

    func requestPermission() async -> Bool {
        // Request speech recognition permission
        let speechStatus = await SFSpeechRecognizer.requestAuthorization()
        guard speechStatus == .authorized else {
            error = "Speech recognition permission denied"
            return false
        }

        // Request microphone permission
        let micStatus = await AVAudioApplication.requestRecordPermission()
        guard micStatus else {
            error = "Microphone permission denied"
            return false
        }

        return true
    }

    // MARK: - Start/Stop

    func startListening() throws {
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw RecognitionError.audioEngineSetupFailed
        }

        let inputNode = audioEngine.inputNode

        // Setup recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw RecognitionError.recognitionRequestFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        // Start recognition task
        guard let speechRecognizer = speechRecognizer else {
            throw RecognitionError.recognizerUnavailable
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    self?.transcript = result.bestTranscription.formattedString

                    // If this is a final result, notify
                    if result.isFinal {
                        NotificationCenter.default.post(
                            name: .speechTranscriptComplete,
                            object: nil,
                            userInfo: ["transcript": result.bestTranscription.formattedString]
                        )
                    }
                }

                if error != nil {
                    self?.stopListening()
                }
            }
        }

        // Install tap on audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        print("[SpeechRecognition] Started listening")
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil

        isListening = false
        print("[SpeechRecognition] Stopped listening")
    }
}

// MARK: - Errors

enum RecognitionError: LocalizedError {
    case audioEngineSetupFailed
    case recognitionRequestFailed
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .audioEngineSetupFailed:
            return "Failed to setup audio engine"
        case .recognitionRequestFailed:
            return "Failed to create recognition request"
        case .recognizerUnavailable:
            return "Speech recognizer unavailable"
        }
    }
}

extension Notification.Name {
    static let speechTranscriptComplete = Notification.Name("speechTranscriptComplete")
}
