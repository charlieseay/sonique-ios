import Foundation
import Speech
import AVFoundation
import os.log

let sttLogger = Logger(subsystem: "com.seayniclabs.sonique", category: "SpeechRecognition")

/// Native on-device STT using Apple's Speech framework.
/// Uses AVAudioEngine voice processing (AEC + automatic gain control) and Apple's
/// own endpointing (result.isFinal) — no custom VAD, no manual gain.
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

    // Endpointing: with .voiceChat the stream stays open and Apple rarely sets
    // isFinal on its own, so we treat a stable partial (unchanged for endpointSilence
    // seconds) as the end of an utterance and submit it.
    private var endpointTimer: Task<Void, Never>?
    private var lastStablePartial = ""
    private let endpointSilence: TimeInterval = 1.3
    private var isRestarting = false
    private(set) var isPausedForPlayback = false

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            error = "Speech recognition permission denied"
            return false
        }
        let micStatus = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard micStatus else {
            error = "Microphone permission denied"
            return false
        }
        return true
    }

    // MARK: - Start/Stop

    func startListening() throws {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            FileTracer.log("[STT] recognizer unavailable")
            throw RecognitionError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        // Audio session: .playAndRecord + .voiceChat enables the system voice-processing
        // path (AEC + AGC). This is what fixes both OSStatus -50 and the quiet-mic problem
        // without any manual gain.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.allowBluetoothHFP, .defaultToSpeaker])
        // Low-latency buffer (5ms) and 16kHz sample rate for speech recognition
        try session.setPreferredIOBufferDuration(0.005)
        try session.setPreferredSampleRate(16000.0)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        FileTracer.log("[STT] session ready (.playAndRecord/.voiceChat). on-device=\(recognizer.supportsOnDeviceRecognition)")

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { throw RecognitionError.audioEngineSetupFailed }
        let inputNode = engine.inputNode

        // Apple's built-in voice processing: hardware/AGC + acoustic echo cancellation.
        // This replaces the custom gain code entirely.
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            FileTracer.log("[STT] voice processing enabled (AEC+AGC)")
        } catch {
            FileTracer.log("[STT] voice processing unavailable: \(error.localizedDescription)")
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { throw RecognitionError.recognitionRequestFailed }
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let format = inputNode.outputFormat(forBus: 0)
        FileTracer.log("[STT] input format \(format.sampleRate)Hz \(format.channelCount)ch")

        engine.prepare()
        try engine.start()
        guard engine.isRunning else { throw RecognitionError.audioEngineSetupFailed }
        FileTracer.log("[STT] engine running")

        lastStablePartial = ""
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.callbackCount += 1
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    FileTracer.log("[STT] result '\(text)' final=\(result.isFinal)")

                    if result.isFinal {
                        self.submit(text)
                        return
                    }

                    // Partial arrived → (re)arm the stability timer. If the transcript
                    // stops changing for endpointSilence seconds, we submit it ourselves.
                    if !text.isEmpty {
                        self.lastStablePartial = text
                        self.armEndpointTimer()
                    }
                }

                if let error {
                    let ns = error as NSError
                    self.lastError = "\(ns.domain) \(ns.code)"
                    // If a pending partial exists, submit it (this IS the end of speech).
                    if !self.lastStablePartial.isEmpty {
                        FileTracer.log("[STT] error \(ns.code) with pending partial → submit")
                        self.submit(self.lastStablePartial)
                        return
                    }
                    // 1110 (no speech) / 301 (canceled) on an empty buffer = normal silence.
                    // The task is already finished; restart ONCE to keep listening.
                    // (restart() is guarded against re-entrancy so this can't storm.)
                    FileTracer.log("[STT] error \(ns.code) (silence) → restart once")
                    self.restart()
                }
            }
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        isListening = true
        FileTracer.log("[STT] LISTENING ✓")
    }

    /// Arm/refresh the endpoint timer. Fires after endpointSilence of no new partials.
    private func armEndpointTimer() {
        endpointTimer?.cancel()
        endpointTimer = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(endpointSilence * 1_000_000_000))
            guard !Task.isCancelled, self.isListening, !self.lastStablePartial.isEmpty else { return }
            FileTracer.log("[STT] endpoint (\(self.endpointSilence)s stable) → submit")
            self.submit(self.lastStablePartial)
        }
    }

    /// Post the recognized utterance and reset for the next one.
    private func submit(_ text: String) {
        endpointTimer?.cancel()
        endpointTimer = nil
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastStablePartial = ""
        guard !final.isEmpty else { restart(); return }
        FileTracer.log("[STT] SUBMIT → posting '\(final)'")
        NotificationCenter.default.post(
            name: .speechTranscriptComplete,
            object: nil,
            userInfo: ["transcript": final]
        )
        restart()
    }

    /// Tear down the current recognition pass and start a fresh one (continuous listening).
    /// Guarded against re-entrancy so a burst of 1110 errors can't spawn a restart storm.
    private func restart() {
        guard !isRestarting else { return }
        isRestarting = true

        endpointTimer?.cancel()
        endpointTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.isRestarting = false
            // Only resume if we're meant to be listening AND not paused for TTS playback.
            guard isListening, !isPausedForPlayback else {
                FileTracer.log("[STT] restart skipped (listening=\(isListening) paused=\(isPausedForPlayback))")
                return
            }
            do { try startListening() }
            catch {
                FileTracer.log("[STT] restart failed: \(error.localizedDescription)")
                self.error = error.localizedDescription
            }
        }
    }

    /// Pause recognition while TTS speaks so the recognizer doesn't hear Sonique's own
    /// voice and so TTS can own the audio session for playback.
    func pauseForPlayback() {
        guard isListening else { return }
        isPausedForPlayback = true
        endpointTimer?.cancel()
        endpointTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        lastStablePartial = ""
        // Fully release the recording session so TTS can switch to .playback without -50.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        FileTracer.log("[STT] paused for TTS playback (session released)")
    }

    /// Resume recognition after TTS finishes.
    func resumeAfterPlayback() {
        guard isListening, isPausedForPlayback else { return }
        isPausedForPlayback = false
        FileTracer.log("[STT] resuming after playback")
        do { try startListening() }
        catch {
            FileTracer.log("[STT] resume failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func stopListening() {
        isListening = false
        endpointTimer?.cancel()
        endpointTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        FileTracer.log("[STT] stopped")
    }
}

// MARK: - Errors

enum RecognitionError: LocalizedError {
    case audioEngineSetupFailed
    case recognitionRequestFailed
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .audioEngineSetupFailed: return "Failed to setup audio engine"
        case .recognitionRequestFailed: return "Failed to create recognition request"
        case .recognizerUnavailable: return "Speech recognizer unavailable"
        }
    }
}

extension Notification.Name {
    static let speechTranscriptComplete = Notification.Name("speechTranscriptComplete")
}
