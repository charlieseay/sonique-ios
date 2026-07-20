import Foundation
import AVFoundation
import Combine

/// Orchestrates the voice loop on top of VoiceSession (single shared engine):
/// listen → submit transcript → stream LLM reply from SoniqueBar → speak sentences
/// through the same engine (AEC prevents echo) → resume listening.
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
    @Published var isAwake = false   // true = responding to all speech; false = needs wake word
    @Published var artifactURL: URL? = nil   // ephemeral image to display (Snapchat-style)
    @Published var debugLog: [String] = []

    /// Seconds of no interaction after a reply before the assistant "sleeps" (then needs
    /// the wake word). 0 = never auto-sleep while the mic is on.
    var sleepAfter: TimeInterval = 30
    private var sleepTimer: Task<Void, Never>?

    /// Hard idle timeout — fully tears down the session (releases mic, closes connections)
    /// to protect battery + data when left running unattended. Reset on every interaction.
    var idleShutdownAfter: TimeInterval = 600   // 10 minutes
    private var idleTimer: Task<Void, Never>?

    /// The currently running processing task (for cancellation during barge-in)
    private var processingTask: Task<Void, Error>?

    @Published private(set) var session: VoiceSession?
    private var sessionObservation: AnyCancellable?
    private var ttsProvider: TTSProvider?

    enum TTSMode: String {
        case voicebox  // VoiceBox/Kokoro via SoniqueBar (best quality)
        case elevenlabs  // ElevenLabs API (premium, costs $)
        case ondevice  // Apple AVSpeechSynthesizer (free fallback)
    }

    private var ttsMode: TTSMode = .elevenlabs  // ElevenLabs direct (no SoniqueBar hop)

    // Back-compat for ContentView
    var speechRecognition: VoiceSession? { session }
    var currentTranscript: String { session?.transcript ?? "" }
    var callbackCount: Int { session?.callbackCount ?? 0 }

    init() {
        Task { await observeTranscripts() }
    }

    // MARK: - Control

    func start() async {
        guard !isActive else { return }
        debugLog.append("Starting...")

        if session == nil {
            isInitializing = true
            let vs = VoiceSession()

            // Check iCloud preferences first to avoid redundant permission prompts
            let prefs = SoniqueBrain.shared.loadPreferences()
            let needsPermission = prefs.permissionsGranted?.speech != true ||
                                  prefs.permissionsGranted?.microphone != true

            if needsPermission {
                guard await vs.requestPermission() else {
                    error = "Microphone or speech permission denied"
                    debugLog.append("ERROR: permission denied")
                    isInitializing = false
                    return
                }
            }
            session = vs
            sessionObservation = vs.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            isInitializing = false
        }

        // Note: checkConnection() is called at app launch via ContentView.task
        // TTS is initialized there, so we don't need to call it again here

        guard let vs = session else { return }
        do {
            FileTracer.reset()
            FileTracer.log("=== LISTEN START (unified engine) ===")
            try vs.configure()
            try vs.start()
            isActive = true
            isAwake = true
            debugLog.append("STT STARTED ✓")
            // Ready cue: crescendo chime, then it's listening.
            SoundCues.shared.playReady()
            armIdleTimer()
        } catch {
            self.error = "Start failed: \(error.localizedDescription)"
            debugLog.append("ERROR: \(error.localizedDescription)")
            FileTracer.log("[loop] START FAILED: \(error)")
        }
    }

    func stop() {
        guard isActive else { return }
        cancelSleepTimer()
        idleTimer?.cancel(); idleTimer = nil
        session?.stop()
        isActive = false
        isProcessing = false
        isAwake = false
        // Sleep cue: decrescendo chime — user will need the wake word next.
        SoundCues.shared.playSleep()
    }

    /// Stop speaking immediately and resume listening (barge-in / interrupt)
    func stopSpeaking() {
        guard isProcessing else { return }
        ttsProvider?.stop()      // Stop TTS playback immediately
        isProcessing = false
        partialResponse = ""
        RemoteLogger.log("[vs] interrupted by user - playback stopped, resumed listening")
    }

    // MARK: - Pipeline

    private func observeTranscripts() async {
        for await notification in NotificationCenter.default.notifications(named: .speechTranscriptComplete) {
            guard let transcript = notification.userInfo?["transcript"] as? String,
                  !transcript.isEmpty else { continue }

            // Ignore duplicate transcripts (stale submissions from before speaking started)
            // Check this FIRST before barge-in logic
            if transcript == lastTranscript {
                RemoteLogger.log("[loop] ignoring duplicate transcript '\(transcript)'")
                continue
            }

            // Barge-in: any new speech while processing cancels the current response.
            if isProcessing {
                let lower = transcript.lowercased()
                RemoteLogger.log("[loop] BARGE-IN DETECTED: '\(transcript)' (isProcessing=true) - cancelling task")
                processingTask?.cancel()
                processingTask = nil
                stopSpeaking()

                // "stop" / "cancel" = just stop talking, don't process a new command.
                if lower == "stop" || lower == "cancel" {
                    RemoteLogger.log("[loop] stop/cancel command - resuming listening (not processing new command)")
                    continue
                }
                RemoteLogger.log("[loop] barge-in with new command '\(transcript)' - will process")
            }

            // Wake-word gating: when asleep, only respond if the user said the assistant's
            // name; strip it from the request. When awake, respond to everything.
            let request: String
            if !isAwake {
                let wake = AssistantProfile.shared.wakeWord
                guard let stripped = WakeWordMatcher.strip(wakeWord: wake, from: transcript) else {
                    FileTracer.log("[loop] asleep, no wake word ('\(wake)') in '\(transcript)' — ignoring")
                    continue
                }
                isAwake = true
                SoundCues.shared.playReady()
                cancelSleepTimer()
                armIdleTimer()
                // Bare wake word, no command → just acknowledge with the chime and listen.
                // Don't burn a 16s LLM round-trip on "Yes?". Arm sleep so it naps again if
                // no follow-up comes.
                if stripped.isEmpty {
                    FileTracer.log("[loop] woke on '\(wake)' (bare) — listening for command")
                    armSleepTimer()
                    continue
                }
                request = stripped
                FileTracer.log("[loop] woke on '\(wake)' → '\(request)'")
            } else {
                request = transcript
            }

            cancelSleepTimer()
            armIdleTimer()   // any interaction resets the 10-min hard-shutdown clock
            // New turn → dismiss any showing artifact (the conversation has organically moved on).
            artifactURL = nil
            isProcessing = true
            objectWillChange.send()  // Force SwiftUI update
            RemoteLogger.log("[loop] START processing request: '\(request)' (isProcessing=true)")
            lastTranscript = request
            partialResponse = ""
            debugLog.append("You: \(request)")

            // Create cancellable task for processing
            processingTask = Task {
                try await processAndSpeak(request)
            }

            do {
                try await processingTask!.value
                RemoteLogger.log("[loop] COMPLETED processing: '\(lastResponse)'")
            } catch is CancellationError {
                RemoteLogger.log("[loop] CANCELLED by barge-in")
            } catch {
                // Never throw an app alert for a transient failure — speak a friendly,
                // retryable message and keep listening.
                debugLog.append("ERROR: \(error.localizedDescription)")
                FileTracer.log("[loop] PIPELINE ERROR (spoken, not alerted): \(error)")

                // Different messages for different error types
                if let httpError = error as? HTTPError, httpError == .streamTimeout {
                    await speakSentence("The connection timed out. Let me try again.")
                    FileTracer.log("[loop] AUTO-RECOVERY: stream timeout, will retry")
                    // Retry the same request once
                    processingTask = Task {
                        try await processAndSpeak(request)
                    }
                    do {
                        try await processingTask!.value
                        RemoteLogger.log("[loop] RETRY SUCCEEDED: '\(lastResponse)'")
                    } catch {
                        await speakSentence("Sorry, I'm still having connection issues. Please try again.")
                        session?.endSpeaking()
                    }
                } else {
                    await speakSentence("Sorry, I ran into an issue. Please try again.")
                    session?.endSpeaking()
                }
            }
            processingTask = nil
            isProcessing = false
            lastTranscript = ""  // Clear to allow same transcript again
            FileTracer.log("[loop] isProcessing = false")
            // After a reply, arm the sleep timer — if no follow-up, go to sleep (needs wake word).
            armSleepTimer()
        }
    }

    // MARK: - Wake word + sleep

    private func armSleepTimer() {
        cancelSleepTimer()
        guard sleepAfter > 0 else { return }
        sleepTimer = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.sleepAfter * 1_000_000_000))
            guard !Task.isCancelled, self.isActive, self.isAwake, !self.isProcessing else { return }
            self.isAwake = false
            SoundCues.shared.playSleep()
            FileTracer.log("[loop] went to sleep — wake word required")
        }
    }

    private func cancelSleepTimer() {
        sleepTimer?.cancel()
        sleepTimer = nil
    }

    /// (Re)arm the hard idle-shutdown timer. After idleShutdownAfter with no interaction,
    /// fully stop — releases the mic + audio session, closing everything to save battery/data.
    private func armIdleTimer() {
        idleTimer?.cancel()
        guard idleShutdownAfter > 0 else { return }
        idleTimer = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.idleShutdownAfter * 1_000_000_000))
            guard !Task.isCancelled, self.isActive, !self.isProcessing else { return }
            FileTracer.log("[loop] idle \(Int(self.idleShutdownAfter))s → full shutdown")
            self.stop()
        }
    }

    private func processAndSpeak(_ transcript: String) async throws {
        guard let vs = session else { return }

        // Pause recognition while we fetch + speak. Engine + session stay live.
        vs.beginSpeaking()

        // On-device native intents first — time/date/battery answered instantly by iOS,
        // no round-trip to SoniqueBar (works offline).
        if let native = NativeIntents.handle(transcript) {
            FileTracer.log("[loop] native intent → '\(native)'")
            lastTranscript = transcript
            lastResponse = native
            await speakSentence(native)
            vs.endSpeaking()
            return
        }

        // Native iOS capabilities — Calendar, Reminders
        if let capabilityResponse = await CapabilityExecutor.shared.execute(transcript) {
            FileTracer.log("[loop] native capability → '\(capabilityResponse)'")
            lastTranscript = transcript
            lastResponse = capabilityResponse
            await speakSentence(capabilityResponse)
            vs.endSpeaking()
            return
        }

        var sentenceBuffer = ""
        var fullResponse = ""

        FileTracer.log("[http] streaming \(HTTPClient.activeBaseURL)/command/stream")
        for try await chunk in HTTPClient.sendCommandStreaming(transcript) {
            // Check for cancellation
            try Task.checkCancellation()

            FileTracer.log("[loop] received chunk: '\(chunk.text)' final=\(chunk.isFinal)")

            // Artifact → show the image (ephemeral). No text on this chunk.
            if let art = chunk.artifactURL, let url = URL(string: art) {
                artifactURL = url
                FileTracer.log("[loop] artifact → \(art)")
                continue
            }
            sentenceBuffer += chunk.text + " "
            fullResponse += chunk.text + " "
            partialResponse = fullResponse.trimmingCharacters(in: .whitespaces)

            let (sentences, remainder) = extractCompleteSentences(from: sentenceBuffer)
            sentenceBuffer = remainder
            for sentence in sentences {
                try Task.checkCancellation()
                await speakSentence(sentence)
            }
        }
        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty { await speakSentence(remaining) }

        lastResponse = fullResponse.trimmingCharacters(in: .whitespaces)
        partialResponse = ""

        // Grow the iCloud brain (mobile folder).
        SoniqueBrain.shared.recordExchange(user: transcript, assistant: lastResponse)

        // Resume listening now that all audio has played.
        vs.endSpeaking()
        FileTracer.log("[loop] resumed listening")
    }

    private func speakSentence(_ sentence: String) async {
        FileTracer.log("[loop] ===== SPEAK SENTENCE START =====")
        FileTracer.log("[loop] Sentence: '\(sentence.prefix(50))'")

        guard let tts = ttsProvider else {
            FileTracer.log("[loop] ❌ NO TTS PROVIDER!")
            return
        }

        guard let vs = session else {
            FileTracer.log("[loop] ❌ NO VOICE SESSION!")
            return
        }

        var clean = sentence.trimmingCharacters(in: .whitespaces)
        // Strip markdown formatting so TTS doesn't read "asterisk asterisk"
        clean = clean.replacingOccurrences(of: "**", with: "")  // Bold
        clean = clean.replacingOccurrences(of: "*", with: "")   // Italic
        clean = clean.replacingOccurrences(of: "`", with: "")   // Code
        clean = clean.replacingOccurrences(of: "_", with: "")   // Underscore emphasis

        guard !clean.isEmpty else {
            FileTracer.log("[loop] ❌ EMPTY after cleaning")
            return
        }

        FileTracer.log("[loop] Cleaned text: '\(clean.prefix(50))'")
        FileTracer.log("[loop] TTS provider type: \(type(of: tts))")
        FileTracer.log("[loop] Fetching PCM...")

        // VoiceBox/ElevenLabs: fetch PCM and play through VoiceSession (routes to Bluetooth)
        if let pcmData = await tts.fetchPCM(clean) {
            FileTracer.log("[loop] ✓✓✓ GOT PCM: \(pcmData.count) bytes")
            FileTracer.log("[loop] Playing via VoiceSession...")
            await withCheckedContinuation { continuation in
                vs.playPCM(data: pcmData) {
                    FileTracer.log("[loop] ✓ Playback complete")
                    continuation.resume()
                }
            }
        } else {
            // No fallback - TTS failed
            FileTracer.log("[loop] ❌ TTS fetchPCM returned NIL - no audio will play")
            // Log error but don't fall back to Apple Voice
        }

        FileTracer.log("[loop] ===== SPEAK SENTENCE END =====")
    }

    private func extractCompleteSentences(from text: String) -> ([String], String) {
        var sentences: [String] = []
        var remainder = text
        let terminators = CharacterSet(charactersIn: ".!?…")
        while let range = remainder.rangeOfCharacter(from: terminators) {
            let after = remainder.index(after: range.lowerBound)
            if after == remainder.endIndex || remainder[after] == " " {
                let sentence = String(remainder[...range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !sentence.isEmpty { sentences.append(sentence) }
                remainder = after < remainder.endIndex
                    ? String(remainder[after...]).trimmingCharacters(in: .init(charactersIn: " "))
                    : ""
            } else { break }
        }
        return (sentences, remainder)
    }

    @Published var connectionOK = true
    @Published var connectionMessage = ""

    /// Probe LAN then Tailscale. On failure, set a friendly, plain-language explanation
    /// (shown on screen) — and speak it once if the user just tried to use it. Never alerts.
    @discardableResult
    func checkConnection(speakIfDown: Bool = false) async -> Bool {
        let result = await HTTPClient.probeConnection()
        connectionOK = result.reachable
        if result.reachable {
            connectionMessage = ""
            FileTracer.log("[conn] reachable via \(result.endpoint ?? "?")")

            // Initialize TTS provider based on mode
            if ttsProvider == nil {
                FileTracer.log("[conn] Initializing TTS provider: \(ttsMode.rawValue)")

                switch ttsMode {
                case .voicebox:
                    ttsProvider = VoiceBoxTTS(soniqueBarHost: Config.soniqueBarHost)
                    debugLog.append("TTS ready (VoiceBox)")
                    FileTracer.log("[conn] VoiceBox TTS initialized")

                case .elevenlabs:
                    do {
                        let apiKey = try await Config.getAPIKey()
                        ttsProvider = ElevenLabsTTS(apiKey: apiKey)
                        debugLog.append("TTS ready (ElevenLabs)")
                        FileTracer.log("[conn] ElevenLabs TTS initialized")
                    } catch {
                        // Fall back to on-device if API key missing
                        FileTracer.log("[conn] ElevenLabs API key missing, falling back to on-device")
                        ttsProvider = SimpleTTS()
                        debugLog.append("TTS ready (on-device fallback)")
                    }

                case .ondevice:
                    ttsProvider = SimpleTTS()
                    debugLog.append("TTS ready (on-device)")
                    FileTracer.log("[conn] On-device TTS initialized")
                }

                self.error = nil
            }
            return true
        }

        let assistant = AssistantProfile.shared.name
        connectionMessage = "\(assistant) can't reach SoniqueBar on your Mac. "
            + "Make sure the Mac is awake, SoniqueBar is running, and you're on the same "
            + "network or connected to Tailscale."
        FileTracer.log("[conn] UNREACHABLE — tried: \(result.triedEndpoints.joined(separator: ", "))")

        if speakIfDown {
            session?.beginSpeaking()
            await speakSentence("I can't reach SoniqueBar on your Mac right now. Make sure it's awake and on the same network, or connected through Tailscale, then try again.")
            session?.endSpeaking()
        }
        return false
    }
}
