import Foundation
import Speech
import AVFoundation
import os.log
import UIKit

let sttLogger = Logger(subsystem: "com.seayniclabs.sonique", category: "SpeechRecognition")

/// Native iOS speech recognition using Apple Speech framework
@MainActor
class SpeechRecognitionService: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var error: String?
    @Published var callbackCount = 0
    @Published var lastError: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var isRestarting = false  // Prevent double-restart on Error 301

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
        guard let recognizer = speechRecognizer else {
            sttLogger.error("Speech recognizer is nil!")
            throw RecognitionError.recognizerUnavailable
        }

        guard recognizer.isAvailable else {
            sttLogger.error("Speech recognizer not available! Locale: \(recognizer.locale.identifier)")
            throw RecognitionError.recognizerUnavailable
        }

        // Check if on-device recognition is supported
        if !recognizer.supportsOnDeviceRecognition {
            sttLogger.warning("On-device recognition NOT supported - will use cloud")
        }

        sttLogger.info("Speech recognizer available, locale: \(recognizer.locale.identifier), on-device: \(recognizer.supportsOnDeviceRecognition)")

        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Setup audio session with Bluetooth support
        let audioSession = AVAudioSession.sharedInstance()
        sttLogger.info("Setting up audio session...")

        // Use .default mode to enable iOS built-in VAD (not .measurement!)
        // .measurement = raw audio, no VAD
        // .default = includes VAD and noise suppression
        try audioSession.setCategory(
            .record,
            mode: .default,
            options: [.allowBluetooth, .duckOthers]
        )

        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        sttLogger.info("Audio session configured - mode: .default (VAD enabled), Bluetooth enabled")

        // Diagnostic: Check audio route
        let route = audioSession.currentRoute
        sttLogger.info("Audio route - inputs: \(route.inputs.map { $0.portName })")
        sttLogger.info("Audio route - outputs: \(route.outputs.map { $0.portName })")
        sttLogger.info("Audio session active: \(audioSession.isOtherAudioPlaying)")

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

        // Only use on-device if supported, otherwise fall back to cloud
        if let recognizer = speechRecognizer, recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
            sttLogger.info("Using on-device recognition")
        } else {
            recognitionRequest.requiresOnDeviceRecognition = false
            sttLogger.info("Using cloud-based recognition (on-device not available)")
        }

        sttLogger.info("Recognition request configured")

        // Install tap on audio input FIRST
        audioEngine.inputNode.removeTap(onBus: 0)  // Remove any existing tap first

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        sttLogger.info("Audio format: \(String(describing: recordingFormat))")
        sttLogger.info("Sample rate: \(recordingFormat.sampleRate), channels: \(recordingFormat.channelCount)")

        // Start audio engine FIRST before installing tap
        sttLogger.info("Preparing audio engine...")
        audioEngine.prepare()
        sttLogger.info("Starting audio engine...")
        try audioEngine.start()
        sttLogger.info("Audio engine start() returned")

        // CRITICAL: Verify engine is actually running
        if !audioEngine.isRunning {
            let errorMsg = "FATAL: audioEngine.start() succeeded but isRunning = FALSE!"
            NSLog("[SONIQUE] %@", errorMsg)
            self.error = errorMsg
            throw RecognitionError.audioEngineSetupFailed
        }
        sttLogger.info("✓ Audio engine confirmed running")

        // Create recognition task BEFORE installing tap (Apple's recommended order)
        guard let speechRecognizer = speechRecognizer else {
            sttLogger.error("No speech recognizer!")
            throw RecognitionError.recognizerUnavailable
        }

        sttLogger.info("Creating recognition task...")
        NSLog("[SONIQUE] Creating recognition task...")

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            NSLog("[SONIQUE] Callback received!")
            var diagnostics = UserDefaults.standard.stringArray(forKey: "SoniqueDiagnostics") ?? []
            diagnostics.append("[\(Date())] Callback received")

            Task { @MainActor in
                self?.callbackCount += 1
                sttLogger.info("🔔 Callback #\(self?.callbackCount ?? 0) received!")

                if let result = result {
                    NSLog("[SONIQUE] Got result: %@", result.bestTranscription.formattedString)
                    let transcript = result.bestTranscription.formattedString
                    diagnostics.append("[\(Date())] Result: '\(transcript)' final=\(result.isFinal)")
                    UserDefaults.standard.set(diagnostics, forKey: "SoniqueDiagnostics")

                    sttLogger.info("Result: '\(transcript)' (isFinal: \(result.isFinal))")
                    self?.transcript = transcript

                    // Write to file for debugging
                    let logStr = "[RESULT] '\(transcript)' isFinal=\(result.isFinal)\n"
                    if let data = logStr.data(using: .utf8),
                       let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("debug.log") {
                        try? data.append(to: url)
                    }

                    // TRUST iOS BUILT-IN VAD - just wait for isFinal=true
                    // iOS will set isFinal=true after ~1-2 seconds of silence
                    // No custom VAD needed!
                    if result.isFinal {
                        // Ignore empty final results
                        guard !transcript.isEmpty else {
                            sttLogger.info("Ignoring empty final result")
                            return
                        }
                        sttLogger.info("🔔 FINAL RESULT - Posting .speechTranscriptComplete notification")
                        NSLog("[SONIQUE] 🔔 Posting notification for transcript: %@", transcript)
                        NotificationCenter.default.post(
                            name: .speechTranscriptComplete,
                            object: nil,
                            userInfo: ["transcript": transcript]
                        )
                        NSLog("[SONIQUE] 🔔 Notification posted successfully")

                        // Mark as restarting to prevent Error 301 double-restart
                        self?.isRestarting = true

                        // Clean up this recognition session
                        self?.recognitionTask?.cancel()
                        self?.recognitionTask = nil
                        self?.recognitionRequest = nil
                        self?.audioEngine?.inputNode.removeTap(onBus: 0)
                        self?.audioEngine?.stop()

                        // Restart recognition for next utterance (continuous listening)
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s gap
                            if let self = self, self.isListening {
                                do {
                                    try self.startListening()
                                    sttLogger.info("✓ Recognition restarted for continuous listening")
                                } catch {
                                    sttLogger.error("Failed to restart after final: \(error.localizedDescription)")
                                }
                                self.isRestarting = false
                            }
                        }
                    }
                }

                if let error = error {
                    let errorCode = (error as NSError).code
                    let errorDomain = (error as NSError).domain
                    NSLog("[SONIQUE] ERROR - Domain: %@, Code: %ld, Desc: %@", errorDomain, errorCode, error.localizedDescription)

                    diagnostics.append("[\(Date())] ERROR: domain=\(errorDomain) code=\(errorCode) msg=\(error.localizedDescription)")
                    UserDefaults.standard.set(diagnostics, forKey: "SoniqueDiagnostics")

                    let fullError = "Domain: \(errorDomain), Code: \(errorCode), Msg: \(error.localizedDescription)"
                    sttLogger.error("Recognition error: \(error.localizedDescription)")
                    sttLogger.error("Error details - domain: \(errorDomain), code: \(errorCode)")
                    self?.lastError = fullError

                    // Error 301 = recognition request canceled (60-second timeout or interruption)
                    // Auto-restart if still listening (skip if already restarting from VAD)
                    if errorCode == 301 && errorDomain == "kLSRErrorDomain" {
                        guard let isRestarting = self?.isRestarting, !isRestarting else {
                            sttLogger.info("Error 301 during VAD restart - ignoring")
                            return
                        }

                        sttLogger.info("Error 301 detected - auto-restarting recognition")
                        diagnostics.append("[\(Date())] Auto-restarting after Error 301")
                        UserDefaults.standard.set(diagnostics, forKey: "SoniqueDiagnostics")

                        self?.isRestarting = true

                        // Clean up current session
                        self?.recognitionTask?.cancel()
                        self?.recognitionTask = nil
                        self?.recognitionRequest = nil
                        self?.audioEngine?.inputNode.removeTap(onBus: 0)
                        self?.audioEngine?.stop()

                        // Restart recognition after brief delay
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                            do {
                                try self?.startListening()
                                sttLogger.info("✓ Recognition auto-restarted successfully")
                            } catch {
                                sttLogger.error("Failed to auto-restart: \(error.localizedDescription)")
                                self?.error = "Failed to restart: \(error.localizedDescription)"
                            }
                            self?.isRestarting = false
                        }
                        return
                    }

                    // For other errors, show alert and stop
                    self?.error = fullError  // Show full error with domain and code

                    // FORCE ALERT for non-301 errors only
                    DispatchQueue.main.async {
                        let alert = UIAlertController(
                            title: "Speech Error",
                            message: "Domain: \(errorDomain)\nCode: \(errorCode)\n\(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))

                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootVC = window.rootViewController {
                            rootVC.present(alert, animated: true)
                        }
                    }

                    // Write error to file for debugging
                    let logStr = "[ERROR] \(fullError)\n"
                    if let data = logStr.data(using: .utf8),
                       let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("debug.log") {
                        try? data.append(to: url)
                    }

                    self?.stopListening()
                }
            }
        }
        sttLogger.info("✓ Recognition task created successfully")

        // NOW install tap AFTER task is created
        inputNode.removeTap(onBus: 0)
        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            bufferCount += 1
            if bufferCount == 1 || bufferCount % 50 == 0 {
                sttLogger.info("Audio buffer #\(bufferCount)")
            }
            self?.recognitionRequest?.append(buffer)

            // No VAD logic here - we use transcript stability detection instead
        }
        sttLogger.info("✓ Audio tap installed, audio will now flow to recognizer")

        isListening = true
        NSLog("[SONIQUE] ✓ LISTENING - audio engine running, recognition task created")
        sttLogger.info("✓ LISTENING - everything started successfully")

        // Write startup success to file
        let logStr = "[STARTED] Listening active, recognizer available, engine running\n"
        if let data = logStr.data(using: .utf8),
           let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("debug.log") {
            try? data.append(to: url)
        }
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

extension Data {
    func append(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let fileHandle = try FileHandle(forWritingTo: url)
            defer { try? fileHandle.close() }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: self)
        } else {
            try write(to: url)
        }
    }
}
