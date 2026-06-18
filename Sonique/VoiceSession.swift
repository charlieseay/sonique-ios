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
    var isSpeaking = false
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

        // Set IO buffer to minimum (64 samples/48kHz = 1.33ms) for low-latency barge-in
        try session.setPreferredIOBufferDuration(64.0 / 48000.0)

        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Auto-route to Bluetooth if available, otherwise speaker
        routeAudioToBestOutput()

        FileTracer.log("[vs] session active (.playAndRecord/.voiceChat, 1.33ms IO buffer)")

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

    /// Route audio to best available output (Bluetooth > Speaker > Earpiece)
    private func routeAudioToBestOutput() {
        let session = AVAudioSession.sharedInstance()
        let currentRoute = session.currentRoute

        // Log available outputs
        FileTracer.log("[vs] Available outputs: \(currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", "))")

        // Check if Bluetooth is already active
        let hasBluetooth = currentRoute.outputs.contains { output in
            output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP || output.portType == .bluetoothLE
        }

        if hasBluetooth {
            FileTracer.log("[vs] Audio routing: Bluetooth (already active)")
            return
        }

        // Check if Bluetooth is available but not active
        let availableInputs = session.availableInputs ?? []
        let hasBluetoothAvailable = availableInputs.contains { input in
            input.portType == .bluetoothHFP
        }

        if hasBluetoothAvailable {
            // Try to activate Bluetooth input (which should also activate Bluetooth output)
            if let bluetoothInput = availableInputs.first(where: { $0.portType == .bluetoothHFP }) {
                do {
                    try session.setPreferredInput(bluetoothInput)
                    FileTracer.log("[vs] Audio routing: Switched to Bluetooth")
                    return
                } catch {
                    FileTracer.log("[vs] Failed to switch to Bluetooth: \(error.localizedDescription)")
                }
            }
        }

        // No Bluetooth - check if using speaker or earpiece
        let usingEarpiece = currentRoute.outputs.contains { $0.portType == .builtInReceiver }
        if usingEarpiece {
            // Switch to speaker
            do {
                try session.overrideOutputAudioPort(.speaker)
                FileTracer.log("[vs] Audio routing: Switched to Speaker (from earpiece)")
            } catch {
                FileTracer.log("[vs] Failed to switch to speaker: \(error.localizedDescription)")
            }
        } else {
            FileTracer.log("[vs] Audio routing: Speaker (default)")
        }
    }

    // MARK: - Recognition

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) {
        endRecognition()  // clean any prior pass

        // Ensure engine is running before installing tap
        if !engine.isRunning {
            FileTracer.log("[vs] engine stopped - restarting before recognition")
            do {
                try engine.start()
                FileTracer.log("[vs] engine restarted")
            } catch {
                FileTracer.log("[vs] ERROR: engine start failed: \(error.localizedDescription)")
                return
            }
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        lastStablePartial = ""
        lastSubmitted = nil  // Reset duplicate prevention for new recognition session

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        do {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                // Always feed the recognizer - AEC handles echo cancellation.
                // This allows barge-in commands like "stop" to be heard while speaking.
                guard let self else { return }
                self.request?.append(buffer)
            }
            FileTracer.log("[vs] tap installed, recognition active")
        } catch {
            FileTracer.log("[vs] ERROR: installTap failed: \(error.localizedDescription)")
            return
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
                    if !text.isEmpty {
                        self.lastStablePartial = text
                        self.armEndpoint()
                        // Post partial transcript for real-time barge-in detection
                        NotificationCenter.default.post(name: .speechTranscriptPartial, object: nil,
                                                        userInfo: ["transcript": text])
                    }
                }
                if let error {
                    let ns = error as NSError
                    self.lastError = "\(ns.domain) \(ns.code)"

                    // Error 1110 = "No speech detected" - this is NORMAL after ~1s silence.
                    // Don't restart, just wait for the next audio input.
                    if ns.code == 1110 {
                        FileTracer.log("[vs] silence timeout (1110) - waiting for speech")
                        return
                    }

                    FileTracer.log("[vs] ERROR: recognition failed: \(ns.domain) \(ns.code) - \(error.localizedDescription)")
                    if !self.lastStablePartial.isEmpty {
                        self.submit(self.lastStablePartial)
                    } else {
                        // 301 or other errors — restart the recognition pass
                        guard self.isListening && !self.isSpeaking else {
                            FileTracer.log("[vs] skipping restart: isListening=\(self.isListening) isSpeaking=\(self.isSpeaking)")
                            return
                        }
                        FileTracer.log("[vs] restarting recognition after error")
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                            guard self.isListening else { return }
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

    private var lastSubmitted: String? = nil  // Prevent duplicate submissions

    private func submit(_ text: String) {
        endpointTimer?.cancel(); endpointTimer = nil
        let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastStablePartial = ""
        guard !final.isEmpty else {
            if isListening, let r = recognizer { beginRecognition(r) }
            return
        }

        // Prevent duplicate submissions of the same transcript
        if final == lastSubmitted {
            FileTracer.log("[vs] DUPLICATE PREVENTED: '\(final)'")
            return
        }

        lastSubmitted = final
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
        // Clear the transcript buffer so we don't re-submit the previous utterance
        transcript = ""
        lastStablePartial = ""
        // Keep recognition running - AEC will prevent speaker output from being heard as input
        FileTracer.log("[vs] begin speaking (recognition active for barge-in, AEC enabled)")
    }

    /// Play raw 16-bit PCM (24kHz mono) through the shared engine's player node.
    func playPCM(_ pcm: Data) async {
        let startTime = Date().timeIntervalSince1970
        FileTracer.log("[vs] playPCM START: \(pcm.count) bytes")

        // Check for cancellation before playing
        guard !Task.isCancelled else {
            FileTracer.log("[vs] playPCM CANCELLED before start [\(Date().timeIntervalSince1970 - startTime)s]")
            return
        }

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

        FileTracer.log("[vs] playPCM: buffer created [\(Date().timeIntervalSince1970 - startTime)s]")

        if !engine.isRunning {
            FileTracer.log("[vs] playPCM: starting engine")
            try? engine.start()
        }
        if !playerNode.isPlaying {
            FileTracer.log("[vs] playPCM: starting player node")
            playerNode.play()
        }

        FileTracer.log("[vs] playPCM: scheduling buffer [\(Date().timeIntervalSince1970 - startTime)s]")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            playbackContinuation = cont
            FileTracer.log("[vs] playPCM: continuation set, calling scheduleBuffer")

            playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    let callbackTime = Date().timeIntervalSince1970
                    FileTracer.log("[vs] playPCM: buffer completion callback fired [\(callbackTime - startTime)s from start]")

                    guard let self, let c = self.playbackContinuation else {
                        FileTracer.log("[vs] playPCM: callback - no continuation to resume")
                        return
                    }
                    self.playbackContinuation = nil
                    c.resume()
                    FileTracer.log("[vs] playPCM: callback - continuation resumed")
                }
            }

            FileTracer.log("[vs] playPCM: scheduleBuffer called, waiting for playback...")
        }

        FileTracer.log("[vs] playPCM: COMPLETE [\(Date().timeIntervalSince1970 - startTime)s]")
    }

    /// Resume recognition after speaking finishes.
    func endSpeaking() {
        isSpeaking = false
        guard isListening, let r = recognizer else { return }
        FileTracer.log("[vs] end speaking → resume recognition")
        // Cancel the old task AND remove the tap to clear any buffered audio
        task?.cancel()
        task = nil
        engine.inputNode.removeTap(onBus: 0)
        // Small delay to ensure tap is fully removed before reinstalling
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard self.isListening else { return }
            self.beginRecognition(r)
        }
    }

    /// Stop playback immediately (for voice barge-in / interrupt)
    func stopPlayback() {
        let startTime = Date().timeIntervalSince1970

        // Disconnect player from mixer to immediately cut audio path
        FileTracer.log("[vs] stopPlayback: disconnecting player node")
        engine.disconnectNodeOutput(playerNode)
        FileTracer.log("[vs] stopPlayback: disconnected [\(Date().timeIntervalSince1970 - startTime)s]")

        // CRITICAL: reset() BEFORE stop() to immediately silence hardware
        // stop() alone waits for scheduled buffers to complete playing
        // reset() clears all buffers immediately, silencing audio
        FileTracer.log("[vs] stopPlayback: resetting player node (clears buffers)")
        playerNode.reset()
        FileTracer.log("[vs] stopPlayback: reset [\(Date().timeIntervalSince1970 - startTime)s]")

        FileTracer.log("[vs] stopPlayback: stopping player node")
        playerNode.stop()
        FileTracer.log("[vs] stopPlayback: stopped [\(Date().timeIntervalSince1970 - startTime)s]")

        // Reconnect for next playback
        FileTracer.log("[vs] stopPlayback: reconnecting player node")
        engine.connect(playerNode, to: engine.mainMixerNode, format: playerFormat)
        FileTracer.log("[vs] stopPlayback: reconnected [\(Date().timeIntervalSince1970 - startTime)s]")

        // Resume any waiting playback continuation so the speak() call completes
        if let cont = playbackContinuation {
            FileTracer.log("[vs] stopPlayback: resuming continuation")
            playbackContinuation = nil
            cont.resume()
            FileTracer.log("[vs] stopPlayback: continuation resumed [\(Date().timeIntervalSince1970 - startTime)s]")
        } else {
            FileTracer.log("[vs] stopPlayback: NO continuation to resume")
        }

        FileTracer.log("[vs] stopPlayback: complete [\(Date().timeIntervalSince1970 - startTime)s]")
    }
}
