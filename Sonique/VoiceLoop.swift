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
    @Published var isSpeaking = false  // True when TTS audio is playing

    // Feature #3: Post-interruption state
    private var interruptedResponse: String?  // Store response that was interrupted
    private var interruptedAt: Date?  // When interruption happened
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

    /// Interruption predictor for distinguishing real interruptions from backchannels
    private let interruptionPredictor = InterruptionPredictor()

    /// Load interruption threshold from AppStorage
    private func syncInterruptionThreshold() {
        let threshold = UserDefaults.standard.float(forKey: "interruption_threshold")
        if threshold > 0 {
            interruptionPredictor.setThreshold(threshold)
        }
    }

    enum TTSMode: String {
        case kokoro  // Kokoro native Swift TTS via SoniqueBar (on-device, free, fast)
        case voicebox  // VoiceBox/Kokoro via SoniqueBar (deprecated - use .kokoro)
        case elevenlabs  // ElevenLabs API (premium, costs $)
        case ondevice  // Apple AVSpeechSynthesizer (free fallback)
    }

    private var ttsMode: TTSMode {
        let stored = UserDefaults.standard.string(forKey: "tts_provider") ?? "kokoro"
        return TTSMode(rawValue: stored) ?? .elevenlabs
    }

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
            syncInterruptionThreshold()  // Load settings threshold
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
        guard isProcessing || isSpeaking else { return }
        ttsProvider?.stop()      // Stop TTS playback immediately
        isProcessing = false
        isSpeaking = false
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

            // Barge-in: check if detected speech is a real interruption vs backchannel
            // Check both isProcessing (LLM streaming) and isSpeaking (TTS playback)
            if isProcessing || isSpeaking {
                // Calculate interruption score using prosodic features
                let duration = 1.0  // TODO: Track actual speech duration from VoiceSession
                let shouldInterrupt = interruptionPredictor.shouldInterrupt(
                    transcript: transcript,
                    duration: duration,
                    energyLevel: nil,  // TODO: Extract from audio buffer
                    pitchVariation: nil,  // TODO: Extract from audio buffer
                    isQuinnSpeaking: true
                )

                if !shouldInterrupt {
                    RemoteLogger.log("[loop] backchannel detected: '\(transcript)' (score below threshold) - ignoring")
                    continue
                }

                let lower = transcript.lowercased()
                RemoteLogger.log("[loop] BARGE-IN DETECTED: '\(transcript)' (isProcessing=true) - cancelling task")

                // Feature #3: Store interrupted state before cancelling
                if !partialResponse.isEmpty {
                    interruptedResponse = partialResponse
                    interruptedAt = Date()
                    RemoteLogger.log("[loop] Stored interrupted response (\(partialResponse.count) chars)")
                }

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

            // Control commands that don't need server processing
            let lower = transcript.lowercased()
            if lower == "stop" || lower == "cancel" || lower == "nevermind" || lower == "never mind" {
                RemoteLogger.log("[loop] control command '\(transcript)' - stopping without server query")
                stopSpeaking()  // Ensure playback stops
                continue
            }

            // Wake-word gating: when asleep, only respond if the user said the assistant's
            // name; strip it from the request. When awake, respond to everything.
            let request: String
            if !isAwake {
                let wake = AssistantProfile.shared.wakeWord

                // Check confidence score (require >= 0.5 to reduce false positives)
                let confidence = WakeWordMatcher.confidence(wakeWord: wake, in: transcript)
                if confidence < 0.5 {
                    FileTracer.log("[loop] asleep, wake word confidence too low (\(String(format: "%.2f", confidence))) in '\(transcript)' — ignoring")
                    continue
                }

                guard let stripped = WakeWordMatcher.strip(wakeWord: wake, from: transcript) else {
                    FileTracer.log("[loop] asleep, no wake word ('\(wake)') in '\(transcript)' — ignoring")
                    continue
                }

                FileTracer.log("[loop] wake word detected with confidence \(String(format: "%.2f", confidence))")
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
            lastTranscript = ""  // Clear so barge-in transcripts aren't filtered as duplicates
            partialResponse = ""
            debugLog.append("You: \(request)")

            // Feature #3: Prepend interrupted context if recent (within 30 seconds)
            var contextualRequest = request
            if let interrupted = interruptedResponse,
               let interruptTime = interruptedAt,
               Date().timeIntervalSince(interruptTime) < 30 {
                contextualRequest = "[INTERRUPTED: I was saying '\(interrupted.prefix(100))...' when interrupted] \(request)"
                RemoteLogger.log("[loop] Adding interrupted context to request")
                // Clear stored interruption after using it
                interruptedResponse = nil
                interruptedAt = nil
            }

            // Create cancellable task for processing
            processingTask = Task {
                try await processAndSpeak(contextualRequest)
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
                    // Report timeout to SoniqueBar for diagnostics
                    await sendFeedback(type: "timeout", message: "Query timed out after 90s", metadata: ["query": String(contextualRequest.prefix(100)), "timeout_seconds": 90])

                    await speakSentence("The connection timed out. Let me try again.")
                    FileTracer.log("[loop] AUTO-RECOVERY: stream timeout, will retry")
                    // Retry the same request once
                    processingTask = Task {
                        try await processAndSpeak(contextualRequest)
                    }
                    do {
                        try await processingTask!.value
                        RemoteLogger.log("[loop] RETRY SUCCEEDED: '\(lastResponse)'")
                    } catch {
                        // Report retry failure
                        await sendFeedback(type: "connection_failure", message: "Retry after timeout also failed", metadata: ["query": String(contextualRequest.prefix(100))])
                        await speakSentence("Sorry, I'm still having connection issues. Please try again.")
                        session?.endSpeaking()
                    }
                } else {
                    // Report general error
                    await sendFeedback(type: "error", message: "Query processing failed: \(error.localizedDescription)", metadata: ["query": String(contextualRequest.prefix(100))])
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
        var chunkCount = 0
        let streamStartTime = Date()

        FileTracer.log("[http] streaming \(HTTPClient.activeBaseURL)/command/stream")
        for try await chunk in HTTPClient.sendCommandStreaming(transcript) {
            // Check for cancellation
            try Task.checkCancellation()

            chunkCount += 1
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

        // Report stream completion metrics
        let streamDuration = Date().timeIntervalSince(streamStartTime)
        await sendFeedback(type: "performance", message: "LLM stream complete", metadata: [
            "chunks": chunkCount,
            "response_length": lastResponse.count,
            "stream_duration_seconds": String(format: "%.2f", streamDuration)
        ])

        // Check for shortcut intent markers from IntentRouter
        if lastResponse.contains("[SHORTCUT:") {
            await executeShortcutIntent(from: lastResponse)
        }

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
            FileTracer.log("[loop] NO TTS PROVIDER!")
            await sendFeedback(type: "error", message: "TTS provider not initialized", metadata: [:])
            return
        }

        guard let vs = session else {
            FileTracer.log("[loop] NO VOICE SESSION!")
            await sendFeedback(type: "error", message: "Voice session not available", metadata: [:])
            return
        }

        var clean = sentence.trimmingCharacters(in: .whitespaces)
        // Strip markdown formatting so TTS doesn't read "asterisk asterisk"
        clean = clean.replacingOccurrences(of: "**", with: "")  // Bold
        clean = clean.replacingOccurrences(of: "*", with: "")   // Italic
        clean = clean.replacingOccurrences(of: "`", with: "")   // Code
        clean = clean.replacingOccurrences(of: "_", with: "")   // Underscore emphasis

        guard !clean.isEmpty else {
            FileTracer.log("[loop] EMPTY after cleaning")
            await sendFeedback(type: "error", message: "Text empty after markdown stripping", metadata: ["original_length": sentence.count])
            return
        }

        FileTracer.log("[loop] Cleaned text: '\(clean.prefix(50))'")
        FileTracer.log("[loop] TTS provider type: \(type(of: tts))")
        FileTracer.log("[loop] Fetching PCM...")

        // Report TTS synthesis start
        await sendFeedback(type: "performance", message: "Starting TTS synthesis", metadata: [
            "text_length": clean.count,
            "provider": String(describing: type(of: tts))
        ])

        let ttsStartTime = Date()

        // VoiceBox/ElevenLabs: fetch PCM and play through VoiceSession (routes to Bluetooth)
        if let pcmData = await tts.fetchPCM(clean) {
            let ttsDuration = Date().timeIntervalSince(ttsStartTime)

            // Report successful TTS completion
            await sendFeedback(type: "performance", message: "TTS synthesis complete", metadata: [
                "audio_size": pcmData.count,
                "synthesis_time_seconds": String(format: "%.2f", ttsDuration),
                "text_length": clean.count
            ])

            isSpeaking = true  // Mark as speaking before playback
            FileTracer.log("[loop] GOT PCM: \(pcmData.count) bytes")
            FileTracer.log("[loop] Playing via VoiceSession...")

            // Report playback start
            await sendFeedback(type: "performance", message: "Starting audio playback", metadata: [
                "audio_size": pcmData.count
            ])

            let playbackStartTime = Date()

            await withCheckedContinuation { continuation in
                vs.playPCM(data: pcmData) {
                    let playbackDuration = Date().timeIntervalSince(playbackStartTime)

                    FileTracer.log("[loop] Playback complete")

                    // Report playback completion
                    Task {
                        await self.sendFeedback(type: "performance", message: "Audio playback complete", metadata: [
                            "playback_duration_seconds": String(format: "%.2f", playbackDuration),
                            "audio_size": pcmData.count
                        ])
                    }

                    self.isSpeaking = false  // Clear speaking flag when done

                    // Resume listening after speaking (continuous conversation mode)
                    do {
                        try vs.start()
                        FileTracer.log("[loop] Resumed listening after TTS")
                    } catch {
                        FileTracer.log("[loop] Failed to resume listening: \(error)")
                        Task {
                            await self.sendFeedback(type: "error", message: "Failed to resume listening after TTS", metadata: ["error": error.localizedDescription])
                        }
                    }

                    continuation.resume()
                }
            }
        } else {
            // No fallback - TTS failed
            FileTracer.log("[loop] TTS fetchPCM returned NIL - no audio will play")

            // Report TTS failure
            await sendFeedback(type: "error", message: "TTS synthesis failed (returned nil)", metadata: [
                "text_length": clean.count,
                "provider": String(describing: type(of: tts))
            ])
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
                case .kokoro:
                    ttsProvider = KokoroTTS(soniqueBarHost: Config.soniqueBarHost)
                    debugLog.append("TTS ready (Kokoro)")
                    FileTracer.log("[conn] Kokoro TTS initialized")

                case .voicebox:
                    ttsProvider = VoiceBoxTTS(soniqueBarHost: Config.soniqueBarHost)
                    debugLog.append("TTS ready (VoiceBox)")
                    FileTracer.log("[conn] VoiceBox TTS initialized")

                case .elevenlabs:
                    // Server-side ElevenLabs TTS (via SoniqueBar)
                    ttsProvider = ElevenLabsDirectTTS(soniqueBarHost: Config.soniqueBarHost)
                    debugLog.append("TTS ready (ElevenLabs)")
                    FileTracer.log("[conn] ElevenLabs TTS initialized (server-side)")

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

    // MARK: - Shortcuts Integration

    /// Parse and execute shortcut intent markers from backend responses
    /// Format: [SHORTCUT:SET_TIMER:10] or [SHORTCUT:TOGGLE_DND:true] or [SHORTCUT:CREATE_REMINDER:text]
    private func executeShortcutIntent(from response: String) async {
        guard let range = response.range(of: "\\[SHORTCUT:[^\\]]+\\]", options: .regularExpression) else {
            return
        }

        let marker = String(response[range])
        FileTracer.log("[shortcuts] Detected intent: \(marker)")

        // Extract components: [SHORTCUT:ACTION:PARAM]
        let parts = marker
            .dropFirst()  // Remove [
            .dropLast()   // Remove ]
            .split(separator: ":")
            .map(String.init)

        guard parts.count >= 2, parts[0] == "SHORTCUT" else {
            FileTracer.log("[shortcuts] Invalid marker format: \(marker)")
            return
        }

        let action = parts[1]
        let param = parts.count > 2 ? parts[2] : ""

        switch action {
        case "SET_TIMER":
            if let minutes = Int(param) {
                let result = await ShortcutsManager.shared.setTimer(minutes: minutes)
                switch result {
                case .success(let message):
                    FileTracer.log("[shortcuts] Timer set: \(message)")
                    await speakSentence(message)
                case .failure(let error):
                    FileTracer.log("[shortcuts] Timer failed: \(error.localizedDescription)")
                    await speakSentence("I couldn't set the timer. \(error.localizedDescription)")
                }
            }

        case "TOGGLE_DND":
            let enable = param == "true"
            let result = await ShortcutsManager.shared.toggleDoNotDisturb(enable: enable)
            switch result {
            case .success(let message):
                FileTracer.log("[shortcuts] DND toggled: \(message)")
                await speakSentence(message)
            case .failure(let error):
                FileTracer.log("[shortcuts] DND failed: \(error.localizedDescription)")
                await speakSentence("I couldn't toggle Do Not Disturb. \(error.localizedDescription)")
            }

        case "CREATE_REMINDER":
            let result = await ShortcutsManager.shared.createReminder(title: param)
            switch result {
            case .success(let message):
                FileTracer.log("[shortcuts] Reminder created: \(message)")
                await speakSentence(message)
            case .failure(let error):
                FileTracer.log("[shortcuts] Reminder failed: \(error.localizedDescription)")
                await speakSentence("I couldn't create the reminder. \(error.localizedDescription)")
            }

        default:
            FileTracer.log("[shortcuts] Unknown action: \(action)")
        }
    }

    // MARK: - Feedback Reporting

    /// Send feedback to SoniqueBar for diagnostics
    private func sendFeedback(type: String, message: String, metadata: [String: Any]) async {
        let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? Config.defaultLANURL
        let authToken = SoniqueBrain.shared.loadPreferences().authToken ?? "5FA5EE09-442D-4969-B091-9AC331E1C39C"

        guard let url = URL(string: "\(serverURL)/feedback") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5

        let payload: [String: Any] = [
            "type": type,
            "message": message,
            "metadata": metadata
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = jsonData

        do {
            _ = try await URLSession.shared.data(for: request)
            FileTracer.log("[feedback] Sent: [\(type)] \(message)")
        } catch {
            // Silent failure
            FileTracer.log("[feedback] Failed: \(error.localizedDescription)")
        }
    }
}
