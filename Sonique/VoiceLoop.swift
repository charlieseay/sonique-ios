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
    private var ttsClient: TTSClient?

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
        guard let vs = session, isProcessing else { return }
        vs.stopPlayback()      // Stop TTS playback immediately
        vs.endSpeaking()       // Resume listening
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

            // Barge-in: if user speaks during processing, cancel the current task and start fresh
            if isProcessing {
                let lower = transcript.lowercased()
                // Check for explicit stop/cancel commands or any new speech
                let shouldBargeIn = lower.contains("stop") || lower.contains("cancel") ||
                                   lower.contains(AssistantProfile.shared.wakeWord.lowercased()) ||
                                   true  // Allow any speech to barge in

                if shouldBargeIn {
                    RemoteLogger.log("[loop] BARGE-IN DETECTED: '\(transcript)' (isProcessing=true) - cancelling task")
                    processingTask?.cancel()
                    processingTask = nil
                    stopSpeaking()

                    // If it's just "stop" or "cancel", just stop talking and resume listening
                    if lower == "stop" || lower == "cancel" {
                        RemoteLogger.log("[loop] stop/cancel command - resuming listening (not processing new command)")
                        continue
                    }
                    // Otherwise fall through to process the new command
                    RemoteLogger.log("[loop] barge-in with new command '\(transcript)' - will process")
                } else {
                    continue
                }
            }

            // Wake-word gating: when asleep, only respond if the user said the assistant's
            // name; strip it from the request. When awake, respond to everything.
            let request: String
            if !isAwake {
                let wake = AssistantProfile.shared.wakeWord
                guard let stripped = stripWakeWord(from: transcript, wake: wake) else {
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

    /// Return the request with the wake word removed if present, else nil.
    /// Matches phonetically — the recognizer often spells a name differently than the user
    /// (e.g. "Cael" → "Kale", "Sonique" → "Sonic"), so exact-string matching fails.
    private func stripWakeWord(from text: String, wake: String) -> String? {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?")) }
            .filter { !$0.isEmpty }

        // Find the first word that sounds like the wake word.
        guard let hitIndex = words.firstIndex(where: { wordMatchesWake($0, wake: wake) }) else {
            return nil
        }

        // Drop the matched word + a leading "hey" if present. Return the remainder.
        let remaining = Array(words[(hitIndex + 1)...])
        // (the wake word may have been preceded by "hey" — already excluded since we keep
        // only words after the hit)
        let result = remaining.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        return result
    }

    /// Does a single spoken word sound like the wake word? Exact, substring, small
    /// edit-distance, or shared phonetic key all count.
    private func wordMatchesWake(_ word: String, wake: String) -> Bool {
        let w = word.lowercased()
        if w == wake || w.contains(wake) || wake.contains(w) { return true }
        if levenshtein(w, wake) <= 1 { return true }
        return phoneticKey(w) == phoneticKey(wake)
    }

    /// A crude phonetic key: drop vowels (except leading), collapse common homophone
    /// consonants (c/k→k, q→k, ph/f→f, s/z→s), dedupe. "cael"→"kl", "kale"→"kl".
    private func phoneticKey(_ s: String) -> String {
        let chars = Array(s.lowercased())
        guard !chars.isEmpty else { return "" }
        var out = ""
        for (i, c) in chars.enumerated() {
            var ch = c
            switch ch {
            case "c", "q", "k": ch = "k"
            case "z": ch = "s"
            case "y": ch = "i"
            default: break
            }
            // keep leading vowel; drop later vowels
            let isVowel = "aeiou".contains(ch)
            if isVowel && i != 0 { continue }
            if out.last == ch { continue }  // dedupe doubles
            out.append(ch)
        }
        return out
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i-1] == b[j-1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost)
            }
            prev = cur
        }
        return prev[b.count]
    }

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

        // Native iOS capabilities — Calendar, Reminders, Messages, Mail, HomeKit
        // Executes locally when possible (Calendar/Reminders/HomeKit API calls)
        let capabilityResponse = await CapabilityExecutor.shared.execute(transcript)
        if capabilityResponse != "I don't recognize that native capability command" {
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
        guard let vs = session, let tts = ttsClient else { return }
        var clean = sentence.trimmingCharacters(in: .whitespaces)
        // Strip markdown formatting so TTS doesn't read "asterisk asterisk"
        clean = clean.replacingOccurrences(of: "**", with: "")  // Bold
        clean = clean.replacingOccurrences(of: "*", with: "")   // Italic
        clean = clean.replacingOccurrences(of: "`", with: "")   // Code
        clean = clean.replacingOccurrences(of: "_", with: "")   // Underscore emphasis
        guard !clean.isEmpty else { return }
        if let pcm = await tts.fetchPCM(clean, voiceID: Config.selectedVoiceID) {
            await vs.playPCM(pcm)
        }
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

            // Initialize TTS after connection is established
            if ttsClient == nil {
                FileTracer.log("[conn] Initializing TTS after connection established")
                do {
                    let apiKey = try await Config.getAPIKey()
                    ttsClient = TTSClient(
                        elevenLabsAPIKey: apiKey,
                        soniqueBarHost: Config.soniqueBarHost
                    )
                    self.error = nil
                    debugLog.append("TTS ready")
                    FileTracer.log("[conn] TTS initialized successfully")
                } catch {
                    self.error = "TTS init failed: \(error.localizedDescription)"
                    debugLog.append("ERROR: TTS - \(error.localizedDescription)")
                    FileTracer.log("[conn] TTS initialization failed: \(error.localizedDescription)")
                }
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
