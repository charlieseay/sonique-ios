import Foundation
import AVFoundation
import WhisperKit
import os.log

let whisperLogger = Logger(subsystem: "com.seayniclabs.sonique", category: "WhisperKitSTT")

/// On-device streaming STT using WhisperKit (Whisper small.en).
/// Replaces SpeechRecognitionService — posts the same .speechTranscriptComplete notification
/// so VoiceLoop requires no changes.
///
/// VAD strategy: energy-based threshold on the raw audio buffer.
/// When RMS energy drops below vadSilenceThreshold for vadSilenceDuration seconds,
/// we treat that as end-of-utterance and fire the final transcript.
@MainActor
class WhisperKitSTTService: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var partialTranscript = ""
    @Published var error: String?
    @Published var callbackCount = 0
    @Published var lastError: String = ""
    @Published var isModelLoaded = false
    @Published var modelLoadProgress: Double = 0.0
    @Published var loadStatus: String = ""        // human-readable: what's happening now
    @Published var loadDetail: String = ""        // sub-line: ETA / instructions

    // VAD parameters (tunable)
    var vadSilenceThreshold: Float = 0.01       // RMS below this = silence
    var vadSilenceDuration: TimeInterval = 1.4  // Seconds of silence to finalize
    var vadMinSpeechDuration: TimeInterval = 0.4 // Min speech before we bother transcribing

    private var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var silenceStartTime: Date?
    private var speechStartTime: Date?
    private var isSpeaking = false
    private var isTranscribing = false
    private var isRestarting = false

    private let sampleRate: Double = 16000  // WhisperKit expects 16kHz
    private let bufferSize: AVAudioFrameCount = 1024

    // MARK: - Setup

    private let modelName = "openai_whisper-base.en"

    func loadModel() async {
        guard whisperKit == nil else { return }
        let model = modelName
        whisperLogger.info("Loading WhisperKit model (\(model))...")

        do {
            // Phase 1: Initialize WhisperKit shell (no download/load yet) so we can
            // check whether the model is already on-device.
            loadStatus = "Preparing voice model"
            loadDetail = "Setting up speech recognition…"
            modelLoadProgress = 0.02

            let config = WhisperKitConfig(
                model: model,
                verbose: false,
                logLevel: .none,
                prewarm: false,   // prewarm doubles peak memory during load — crashes on device
                load: false,      // don't auto-load; we drive download + load with progress
                download: false
            )
            let wk = try await WhisperKit(config)

            // Phase 2: Download the model with real progress. WhisperKit.download is a
            // fast no-op if the model is already cached on-device (returns existing folder).
            loadStatus = "Downloading voice model"
            loadDetail = "≈70 MB · first launch only · keep WiFi on"
            modelLoadProgress = 0.05

            let modelFolderURL = try await WhisperKit.download(
                variant: model,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        // Download spans 0.05 → 0.80 of the bar
                        let frac = progress.fractionCompleted
                        self.modelLoadProgress = 0.05 + frac * 0.75
                        let pct = Int(frac * 100)
                        self.loadDetail = "≈70 MB · \(pct)% · keep WiFi on"
                    }
                }
            )

            // Phase 3: Load the model into memory.
            loadStatus = "Loading voice model"
            loadDetail = "Almost ready…"
            modelLoadProgress = 0.85
            wk.modelFolder = modelFolderURL
            try await wk.loadModels()

            whisperKit = wk
            isModelLoaded = true
            modelLoadProgress = 1.0
            loadStatus = "Ready"
            loadDetail = "Tap the mic and start speaking"
            whisperLogger.info("✓ WhisperKit model loaded")
        } catch {
            let msg = "Voice model failed to load: \(error.localizedDescription)"
            self.error = msg
            self.lastError = msg
            self.loadStatus = "Load failed"
            self.loadDetail = "Tap to retry"
            modelLoadProgress = 0.0
            whisperLogger.error("\(msg)")
        }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
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
        guard isModelLoaded else {
            throw STTError.modelNotLoaded
        }
        guard !isListening else { return }

        whisperLogger.info("Configuring audio session (.playAndRecord, .voiceChat)...")

        let session = AVAudioSession.sharedInstance()
        // .voiceChat enables AEC + live duplex — fixes OSStatus -50 by avoiding .record + .default conflict
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .defaultToSpeaker, .duckOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        whisperLogger.info("Audio session ready. Setting up engine...")

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw STTError.audioEngineSetupFailed
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        whisperLogger.info("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

        // We need to downsample to 16kHz for WhisperKit
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw STTError.audioEngineSetupFailed
        }

        inputNode.removeTap(onBus: 0)

        // Install tap — we'll convert to 16kHz inside the tap
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: whisperFormat)
        }

        engine.prepare()
        try engine.start()

        guard engine.isRunning else {
            throw STTError.audioEngineSetupFailed
        }

        audioBuffer = []
        silenceStartTime = nil
        speechStartTime = nil
        isSpeaking = false
        isListening = true

        whisperLogger.info("✓ WhisperKit STT listening — engine running, VAD active")
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        audioBuffer = []
        isSpeaking = false
        isListening = false
        whisperLogger.info("WhisperKit STT stopped")
    }

    // MARK: - Audio Processing + VAD

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Convert to 16kHz if needed
        let samples: [Float]
        if inputFormat.sampleRate != sampleRate {
            samples = downsample(channelData, frameCount: frameCount, fromRate: inputFormat.sampleRate, toRate: sampleRate)
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        // RMS energy for VAD
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let now = Date()

        Task { @MainActor in
            if rms > vadSilenceThreshold {
                // Speech detected
                if !isSpeaking {
                    isSpeaking = true
                    speechStartTime = now
                    silenceStartTime = nil
                    whisperLogger.info("VAD: speech started (RMS: \(String(format: "%.4f", rms)))")
                }
                silenceStartTime = nil
                audioBuffer.append(contentsOf: samples)

            } else {
                // Silence
                if isSpeaking {
                    if silenceStartTime == nil {
                        silenceStartTime = now
                    }

                    // Keep buffering during silence (don't drop the tail audio)
                    audioBuffer.append(contentsOf: samples)

                    let silenceElapsed = now.timeIntervalSince(silenceStartTime!)
                    let speechElapsed = speechStartTime.map { now.timeIntervalSince($0) } ?? 0

                    if silenceElapsed >= vadSilenceDuration {
                        // End of utterance
                        isSpeaking = false
                        silenceStartTime = nil

                        if speechElapsed >= vadMinSpeechDuration && !audioBuffer.isEmpty && !isTranscribing {
                            let capturedBuffer = audioBuffer
                            audioBuffer = []
                            whisperLogger.info("VAD: end of speech (\(String(format: "%.1f", speechElapsed))s) — transcribing \(capturedBuffer.count) samples")
                            await transcribeBuffer(capturedBuffer)
                        } else {
                            audioBuffer = []
                        }

                        speechStartTime = nil
                    }
                }
                // Not speaking + silence: discard
            }
        }
    }

    private func downsample(_ input: UnsafeMutablePointer<Float>, frameCount: Int, fromRate: Double, toRate: Double) -> [Float] {
        let ratio = fromRate / toRate
        let outputCount = Int(Double(frameCount) / ratio)
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Int(Double(i) * ratio)
            if srcIndex < frameCount {
                output[i] = input[srcIndex]
            }
        }
        return output
    }

    // MARK: - Transcription

    private func transcribeBuffer(_ samples: [Float]) async {
        guard let wk = whisperKit, !isTranscribing else { return }
        isTranscribing = true

        do {
            let results = try await wk.transcribe(audioArray: samples)
            let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            self.callbackCount += 1
            whisperLogger.info("Transcript #\(self.callbackCount): '\(text)'")

            guard !text.isEmpty else {
                isTranscribing = false
                return
            }

            transcript = text
            partialTranscript = ""

            // Post the same notification VoiceLoop already listens for
            NotificationCenter.default.post(
                name: .speechTranscriptComplete,
                object: nil,
                userInfo: ["transcript": text]
            )
            whisperLogger.info("✓ Posted .speechTranscriptComplete: '\(text)'")

        } catch {
            lastError = error.localizedDescription
            whisperLogger.error("Transcription failed: \(error.localizedDescription)")
        }

        isTranscribing = false
    }
}

// MARK: - Errors

enum STTError: LocalizedError {
    case modelNotLoaded
    case audioEngineSetupFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "WhisperKit model not loaded yet"
        case .audioEngineSetupFailed: return "Failed to setup audio engine"
        }
    }
}
