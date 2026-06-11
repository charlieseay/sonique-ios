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
    @Published var liveRMS: Float = 0             // current mic RMS (for on-screen meter)
    @Published var debugLines: [String] = []      // on-screen VAD/transcript trace

    // VAD parameters (tunable)
    // Wired trace showed .voiceChat+.duckOthers attenuates mic ~10×: speech peaked at
    // only 0.0024 RMS. Threshold dropped to 0.0008 + we apply input gain below.
    var vadSilenceThreshold: Float = 0.0008     // RMS below this = silence
    var vadSilenceDuration: TimeInterval = 1.2  // Seconds of silence to finalize
    var vadMinSpeechDuration: TimeInterval = 0.3 // Min speech before we bother transcribing
    var inputGain: Float = 8.0                  // Compensate for .voiceChat attenuation

    private var peakRMSThisUtterance: Float = 0
    private func dbg(_ s: String) {
        debugLines.append(s)
        if debugLines.count > 40 { debugLines.removeFirst(debugLines.count - 40) }
        FileTracer.log("[STT] \(s)")
    }

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
        // .voiceChat enables AEC + live duplex — fixes OSStatus -50 by avoiding .record + .default conflict.
        // Dropped .duckOthers — it was attenuating mic input ~10× (wired trace: speech peaked 0.0024 RMS).
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .defaultToSpeaker]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Crank hardware input gain to max if the device exposes a settable gain.
        if session.isInputGainSettable {
            try? session.setInputGain(1.0)
            whisperLogger.info("Input gain set to 1.0 (was \(session.inputGain))")
        }

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

    private var tapCount = 0
    private var maxRMSSeen: Float = 0

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Convert to 16kHz if needed
        var samples: [Float]
        if inputFormat.sampleRate != sampleRate {
            samples = downsample(channelData, frameCount: frameCount, fromRate: inputFormat.sampleRate, toRate: sampleRate)
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        // Apply input gain to compensate for .voiceChat attenuation, clamped to [-1, 1].
        let gain = inputGain
        if gain != 1.0 {
            for i in samples.indices {
                samples[i] = max(-1.0, min(1.0, samples[i] * gain))
            }
        }

        // RMS energy for VAD (on the gained signal)
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let now = Date()

        Task { @MainActor in
            liveRMS = rms
            tapCount += 1
            maxRMSSeen = max(maxRMSSeen, rms)
            // Heartbeat every ~50 taps (~1s) so we can SEE the tap is firing + peak level
            if tapCount % 50 == 0 {
                dbg("🔊 tap#\(tapCount) live \(String(format: "%.4f", rms)) peak \(String(format: "%.4f", maxRMSSeen))")
            }

            if rms > vadSilenceThreshold {
                // Speech detected
                if !isSpeaking {
                    isSpeaking = true
                    speechStartTime = now
                    silenceStartTime = nil
                    peakRMSThisUtterance = rms
                    dbg("🎤 speech start (rms \(String(format: "%.4f", rms)))")
                    whisperLogger.info("VAD: speech started (RMS: \(String(format: "%.4f", rms)))")
                }
                peakRMSThisUtterance = max(peakRMSThisUtterance, rms)
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
                            dbg("⏹ end \(String(format: "%.1f", speechElapsed))s peak \(String(format: "%.4f", peakRMSThisUtterance)) — transcribing \(capturedBuffer.count) samp")
                            whisperLogger.info("VAD: end of speech (\(String(format: "%.1f", speechElapsed))s) — transcribing \(capturedBuffer.count) samples")
                            await transcribeBuffer(capturedBuffer)
                        } else {
                            dbg("⏹ dropped (\(String(format: "%.1f", speechElapsed))s < min, or empty)")
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

    /// True if the transcript is a Whisper non-speech hallucination (sound tags, lone
    /// punctuation) rather than real spoken words. Whisper emits these on silent/garbled audio.
    private func isHallucinatedNonSpeech(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }

        // Strip every (...), [...], *...* group; if nothing meaningful remains, it's a tag-only line.
        let stripped = text
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\*[^*]*\*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remaining must contain at least one letter/number to count as real speech.
        let hasAlphanumeric = stripped.rangeOfCharacter(from: .alphanumerics) != nil
        if !hasAlphanumeric { return true }

        // Known thank-you/subscribe hallucinations Whisper emits on silence.
        let lower = stripped.lowercased()
        let knownGarbage = ["thank you.", "thanks for watching.", "you", "."]
        if knownGarbage.contains(lower) { return true }

        return false
    }

    // MARK: - Transcription

    private func transcribeBuffer(_ samples: [Float]) async {
        guard let wk = whisperKit, !isTranscribing else { return }
        isTranscribing = true

        do {
            let results = try await wk.transcribe(audioArray: samples)
            let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            self.callbackCount += 1
            dbg("📝 transcript: '\(text)'")
            whisperLogger.info("Transcript #\(self.callbackCount): '\(text)'")

            guard !text.isEmpty else {
                dbg("⚠️ empty transcript — nothing recognized")
                isTranscribing = false
                return
            }

            // Filter Whisper's non-speech hallucinations on near-silent/garbled audio:
            // bracketed/parenthetical sound tags like "(sighs)", "[music]", "(sadly)",
            // "*laughs*", and lone punctuation. These poison the LLM (the "why are you sad" loop).
            if isHallucinatedNonSpeech(text) {
                dbg("🚫 filtered non-speech: '\(text)'")
                whisperLogger.info("Filtered Whisper non-speech hallucination: '\(text)'")
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
