import AVFoundation
import Speech
import os

/// Listens passively for "Hey Cal" using on-device speech recognition.
/// Stop before calling SessionManager.connect() so the audio input node
/// is released before LiveKit takes over the session.
/// Battery note: SFSpeechRecognizer uses more power than a dedicated wake
/// word engine like Porcupine. Toggle off when not needed.
@MainActor
final class WakeWordDetector: ObservableObject {
    @Published private(set) var isListening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var cycleTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.seayniclabs.sonique", category: "WakeWordDetector")

    var onDetected: (() -> Void)?

    func start() {
        guard !isListening else { return }
        Task { @MainActor in await self.authorizeAndStart() }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        cycleTask?.cancel()
        cycleTask = nil
        teardown()
        logger.info("wake_word_stopped")
    }

    private func authorizeAndStart() async {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            logger.warning("wake_word: microphone not authorized")
            return
        }
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            logger.warning("wake_word: speech recognition not authorized status=\(status.rawValue)")
            return
        }
        do {
            try startCycle()
            isListening = true
            logger.info("wake_word_started")
        } catch {
            logger.error("wake_word_start_failed: \(error.localizedDescription)")
        }
    }

    private func startCycle() throws {
        teardown()
        guard let recognizer, recognizer.isAvailable else {
            throw WakeWordError.recognizerUnavailable
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        recognitionRequest = req

        let engine = AVAudioEngine()
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
        }
        engine.prepare()
        try engine.start()
        audioEngine = engine

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if let result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    if self.isWakePhrase(text) {
                        self.logger.info("wake_word_detected: \(text, privacy: .public)")
                        self.onDetected?()
                        self.scheduleRestart(after: 2.5)
                        return
                    }
                    if result.isFinal { self.scheduleRestart(after: 0.05) }
                }
                if let error {
                    let code = (error as NSError).code
                    if code != 1110 { self.logger.info("wake_word_cycle_end code=\(code)") }
                    self.scheduleRestart(after: 0.1)
                }
            }
        }
        scheduleRestart(after: 4.0)
    }

    private func isWakePhrase(_ text: String) -> Bool {
        text.contains("hey cal") || text.contains("hey kal") || text.contains("heykal")
    }

    private func scheduleRestart(after delay: TimeInterval) {
        cycleTask?.cancel()
        cycleTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, self.isListening else { return }
            do {
                try self.startCycle()
            } catch {
                self.logger.error("wake_word_restart_failed: \(error.localizedDescription)")
                self.isListening = false
            }
        }
    }

    private func teardown() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    enum WakeWordError: Error {
        case recognizerUnavailable
    }
}
