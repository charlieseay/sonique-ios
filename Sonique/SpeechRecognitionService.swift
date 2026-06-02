import Foundation
import Speech
import AVFoundation
import os.log

let sttLogger = Logger(subsystem: "com.seayniclabs.sonique", category: "SpeechRecognition")

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
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            error = "Speech recognition permission denied"
            return false
        }

        // Request microphone permission
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micStatus else {
            error = "Microphone permission denied"
            return false
        }

        return true
    }

    // MARK: - Start/Stop

    func startListening() throws {
        // Check if speech recognizer is available
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            sttLogger.error("Speech recognizer not available!")
            throw RecognitionError.recognizerUnavailable
        }
        sttLogger.info("Speech recognizer is available, locale: \(recognizer.locale.identifier)")

        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        sttLogger.info("Setting up audio session...")
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        sttLogger.info("Audio session active")

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
                    let transcript = result.bestTranscription.formattedString
                    sttLogger.info("Result: '\(transcript)' (isFinal: \(result.isFinal))")
                    self?.transcript = transcript

                    // If this is a final result, notify
                    if result.isFinal {
                        sttLogger.info("Final result - posting notification")
                        NotificationCenter.default.post(
                            name: .speechTranscriptComplete,
                            object: nil,
                            userInfo: ["transcript": transcript]
                        )
                    }
                }

                if let error = error {
                    sttLogger.error("Recognition error: \(error.localizedDescription)")
                    self?.stopListening()
                }
            }
        }

        // Install tap on audio input
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        sttLogger.info("Audio format: \(String(describing: recordingFormat))")

        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            bufferCount += 1
            if bufferCount % 100 == 0 {
                sttLogger.info("Received \(bufferCount) audio buffers")
            }
            self.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        sttLogger.info("Started listening - audio engine running")
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil

        // Deactivate audio session so TTS can play
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

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
