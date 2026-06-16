import Foundation
import Speech
import AVFoundation

/// Single AVAudioEngine that hosts BOTH the speech-recognition input tap and the
/// TTS player node, per Apple's guidance: acoustic echo cancellation only works when
/// mic input and speaker output share one engine. This is the Siri / voice-assistant
/// pattern — a persistent .playAndRecord/.voiceChat session, voice processing on the
/// input node, and a player node for playback. No session teardown between turns.
@MainActor
class VoiceSession: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var callbackCount = 0
    @Published var lastError = ""
    @Published var error: String?

    // One engine for the whole session.
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var playerFormat: AVAudioFormat!

    // Recognition
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // Endpointing (stable-partial → submit)
    private var endpointTimer: Task<Void, Never>?
    private var lastStablePartial = ""
    private let endpointSilence: TimeInterval = 1.2

    // TTS playback gating
    private var isSpeaking = false
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { error = "Speech permission denied"; return false }
        let mic = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard mic else { error = "Microphone permission denied"; return false }

        // Save permission state to iCloud
        var prefs = SoniqueBrain.shared.loadPreferences()
        prefs.permissionsGranted = SoniqueBrain.Preferences.PermissionState(
            speech: true,
            microphone: true
        )
        SoniqueBrain.shared.savePreferences(prefs)

        return true
    }

    // MARK: - Lifecycle

    /// Configure the persistent session + engine once. Call before start().
    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        FileTracer.log("[vs] session active (.playAndRecord/.voiceChat)")

        let input = engine.inputNode
        // Voice processing on the input node = AEC + AGC. With the player node on the
        // same engine, this cancels Sonique's own TTS out of the mic signal (no echo).
        do {
            try input.setVoiceProcessingEnabled(true)
            FileTracer.log("[vs] voice processing enabled (AEC+AGC)")
        } catch {
            FileTracer.log("[vs] voice processing unavailable: \(error.localizedDescription)")
        }

        // Player node for TTS. ElevenLabs gives 24kHz mono 16-bit PCM.
        playerFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                     sampleRate: 24000, channels: 1, interleaved: false)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playerFormat)

        engine.prepare()
        try engine.start()
        FileTracer.log("[vs] engine running (shared input+player)")
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw RecognitionError.recognizerUnavailable
        }
        if !engine.isRunning { try configure() }
        beginRecognition(recognizer)
        isListening = true
        FileTracer.log("[vs] LISTENING ✓")
    }

    func stop() {
        isListening = false
        endpointTimer?.cancel(); endpointTimer = nil
        endRecognition()
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        FileTracer.log("[vs] stopped")
    }

    // MARK: - Recognition

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) {
        endRecognition()  // clean any prior pass

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        lastStablePartial = ""

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Don't feed the recognizer while Sonique is speaking (belt-and-suspenders
            // on top of AEC) so a residual echo can't be transcribed.
            guard let self, !self.isSpeakingNow() else { return }
            self.request?.append(buffer)
        }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.callbackCount += 1
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    FileTracer.log("[vs] result '\(text)' final=\(result.isFinal)")
                    if result.isFinal { self.submit(text); return }
                    if !text.isEmpty { self.lastStablePartial = text; self.armEndpoint() }
                }
                if let error {
                    let ns = error as NSError
                    self.lastError = "\(ns.domain) \(ns.code)"
                    if !self.lastStablePartial.isEmpty {
                        self.submit(self.lastStablePartial)
                    } else {
                        // 1110/301 silence — restart the recognition pass only (engine stays up).
                        if self.isListening && !self.isSpeaking {
                            self.beginRecognition(recognizer)
                        }
                    }
                }
            }
        }
    }

    private func endRecognition() {
        task?.cancel(); task = nil
        request = nil
    }

    private func armEndpoint() {
        endpointTimer?.cancel()
        endpointTimer = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(endpointSilence * 1_000_000_000))
            guard !Task.isCancelled, self.isListening, !self.lastStablePartial.isEmpty else { return }
            FileTracer.log("[vs] endpoint (\(self.endpointSilence)s) → submit")
            self.submit(self.lastStablePartial)
        }
    }

    private func submit(_ text: String) {
        endpointTimer?.cancel(); endpointTimer = nil
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastStablePartial = ""
        guard !final.isEmpty else {
            if isListening, let r = recognizer { beginRecognition(r) }
            return
        }
        FileTracer.log("[vs] SUBMIT '\(final)'")
        NotificationCenter.default.post(name: .speechTranscriptComplete, object: nil,
                                        userInfo: ["transcript": final])
        // Caller (VoiceLoop) will speak, then call resumeListening(); meanwhile pause input.
    }

    // MARK: - TTS playback (same engine → AEC cancels echo)

    private func isSpeakingNow() -> Bool { isSpeaking }

    /// Begin speaking but keep recognition running for barge-in (AEC prevents echo).
    func beginSpeaking() {
        isSpeaking = true
        endpointTimer?.cancel(); endpointTimer = nil
        // Keep recognition running - AEC will prevent speaker output from being heard as input
        FileTracer.log("[vs] begin speaking (recognition active for barge-in, AEC enabled)")
    }

    /// Play raw 16-bit PCM (24kHz mono) through the shared engine's player node.
    func playPCM(_ pcm: Data) async {
        guard pcm.count > 1 else { return }
        let frames = AVAudioFrameCount(pcm.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frames),
              let channel = buffer.int16ChannelData?[0] else {
            FileTracer.log("[vs] PCM buffer alloc failed")
            return
        }
        buffer.frameLength = frames
        pcm.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            channel.update(from: src.baseAddress!, count: Int(frames))
        }
        if !engine.isRunning { try? engine.start() }
        if !playerNode.isPlaying { playerNode.play() }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let c = self.playbackContinuation else { return }
                    self.playbackContinuation = nil
                    c.resume()
                }
            }
        }
    }

    /// Resume recognition after speaking finishes.
    func endSpeaking() {
        isSpeaking = false
        guard isListening, let r = recognizer else { return }
        FileTracer.log("[vs] end speaking → resume recognition")
        beginRecognition(r)
    }

    /// Stop playback immediately (for voice barge-in / interrupt)
    func stopPlayback() {
        playerNode.stop()
        FileTracer.log("[vs] playback stopped (barge-in)")
    }
}
