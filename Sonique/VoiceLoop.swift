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
    @Published var debugLog: [String] = []

    /// Seconds of no interaction after a reply before the assistant "sleeps" (then needs
    /// the wake word). 0 = never auto-sleep while the mic is on.
    var sleepAfter: TimeInterval = 30
    private var sleepTimer: Task<Void, Never>?

    @Published private(set) var session: VoiceSession?
    private var sessionObservation: AnyCancellable?
    private var ttsClient: ElevenLabsTTSClient?

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
            guard await vs.requestPermission() else {
                error = "Microphone or speech permission denied"
                debugLog.append("ERROR: permission denied")
                isInitializing = false
                return
            }
            session = vs
            sessionObservation = vs.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            do {
                let apiKey = try await Config.getAPIKey()
                ttsClient = ElevenLabsTTSClient(apiKey: apiKey)
                debugLog.append("TTS ready")
            } catch {
                self.error = "TTS init failed: \(error.localizedDescription)"
                debugLog.append("ERROR: TTS - \(error.localizedDescription)")
                isInitializing = false
                return
            }
            isInitializing = false
        }

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
        } catch {
            self.error = "Start failed: \(error.localizedDescription)"
            debugLog.append("ERROR: \(error.localizedDescription)")
            FileTracer.log("[loop] START FAILED: \(error)")
        }
    }

    func stop() {
        guard isActive else { return }
        session?.stop()
        isActive = false
        isProcessing = false
        isAwake = false
        // Sleep cue: decrescendo chime — user will need the wake word next.
        SoundCues.shared.playSleep()
    }

    // MARK: - Pipeline

    private func observeTranscripts() async {
        for await notification in NotificationCenter.default.notifications(named: .speechTranscriptComplete) {
            guard let transcript = notification.userInfo?["transcript"] as? String,
                  !transcript.isEmpty else { continue }

            if isProcessing { continue }  // ignore overlaps; barge-in handled by AEC + pause

            // Wake-word gating: when asleep, only respond if the user said the assistant's
            // name; strip it from the request. When awake, respond to everything.
            var request = transcript
            if !isAwake {
                let wake = AssistantProfile.shared.wakeWord
                guard let stripped = stripWakeWord(from: transcript, wake: wake) else {
                    FileTracer.log("[loop] asleep, no wake word ('\(wake)') in '\(transcript)' — ignoring")
                    continue
                }
                isAwake = true
                SoundCues.shared.playReady()
                request = stripped.isEmpty ? "Yes?" : stripped
                FileTracer.log("[loop] woke on '\(wake)' → '\(request)'")
            }

            cancelSleepTimer()
            isProcessing = true
            lastTranscript = request
            partialResponse = ""
            debugLog.append("You: \(request)")
            FileTracer.log("[loop] transcript: '\(request)' → SoniqueBar")

            do {
                try await processAndSpeak(request)
                FileTracer.log("[loop] done: '\(lastResponse)'")
            } catch {
                self.error = error.localizedDescription
                debugLog.append("ERROR: \(error.localizedDescription)")
                FileTracer.log("[loop] PIPELINE ERROR: \(error)")
                session?.endSpeaking()
            }
            isProcessing = false
            // After a reply, arm the sleep timer — if no follow-up, go to sleep (needs wake word).
            armSleepTimer()
        }
    }

    // MARK: - Wake word + sleep

    /// Return the request with the wake word removed if present, else nil.
    private func stripWakeWord(from text: String, wake: String) -> String? {
        let lower = text.lowercased()
        guard lower.contains(wake) else { return nil }
        // Remove the wake word and common filler around it ("hey <wake>", "<wake>,").
        var out = text
        for variant in ["hey \(wake)", wake] {
            if let range = out.lowercased().range(of: variant) {
                out.removeSubrange(range)
                break
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
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

        var sentenceBuffer = ""
        var fullResponse = ""

        FileTracer.log("[http] streaming \(Config.commandServerURL)/command/stream")
        for try await chunk in HTTPClient.sendCommandStreaming(transcript) {
            sentenceBuffer += chunk.text + " "
            fullResponse += chunk.text + " "
            partialResponse = fullResponse.trimmingCharacters(in: .whitespaces)

            let (sentences, remainder) = extractCompleteSentences(from: sentenceBuffer)
            sentenceBuffer = remainder
            for sentence in sentences {
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
        let clean = sentence.trimmingCharacters(in: .whitespaces)
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

    func checkConnection() async -> Bool {
        do { return try await HTTPClient.healthCheck() }
        catch { self.error = "Cannot reach SoniqueBar: \(error.localizedDescription)"; return false }
    }
}
