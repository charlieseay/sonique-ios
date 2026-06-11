import Foundation
import AVFoundation

/// ElevenLabs TTS client for streaming audio playback
@MainActor
class ElevenLabsTTSClient: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var error: String?

    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private let apiKey: String
    private var sentenceQueue: [String] = []
    private var isQueueRunning = false
    var useSpeedMode = false  // AVSpeechSynthesizer fallback

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        setupAudioEngine()
    }

    // MARK: - Sentence Queue (streaming pipeline)

    func enqueueSentence(_ sentence: String) {
        sentenceQueue.append(sentence)
        if !isQueueRunning {
            Task { await processSentenceQueue() }
        }
    }

    func interrupt() {
        sentenceQueue.removeAll()
        audioPlayerNode?.stop()
        isPlaying = false
        isQueueRunning = false
    }

    private func processSentenceQueue() async {
        isQueueRunning = true
        while !sentenceQueue.isEmpty {
            let sentence = sentenceQueue.removeFirst()
            do {
                try await speak(sentence, voice: Config.selectedVoice)
            } catch {
                print("[TTS] Queue sentence error: \(error.localizedDescription)")
            }
        }
        isQueueRunning = false
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let playerNode = audioPlayerNode else { return }

        engine.attach(playerNode)

        // ElevenLabs outputs 24kHz audio
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)

        if let format = format {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }

        do {
            try engine.start()
        } catch {
            self.error = "Audio engine failed to start: \(error.localizedDescription)"
            print("[TTS] Audio engine error: \(error)")
        }
    }

    // MARK: - Text to Speech

    func speak(_ text: String, voice: ElevenLabsVoice = .josh) async throws {
        guard !text.isEmpty else { return }

        // Configure audio session for playback
        let audioSession = AVAudioSession.sharedInstance()

        // Use .playback with options for Bluetooth + volume control
        try audioSession.setCategory(
            .playback,
            mode: .spokenAudio,  // Optimized for voice content
            options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
        )

        try audioSession.setActive(true)

        print("[TTS] Audio session configured - category: playback, mode: spokenAudio, Bluetooth enabled")

        isPlaying = true
        print("[TTS] Speaking: \(text)")

        // Call ElevenLabs TTS API
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice.rawValue)/stream")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_monolingual_v1",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Stream audio response
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TTSError.apiError
        }

        // Collect audio data
        var audioData = Data()
        for try await byte in bytes {
            audioData.append(byte)
        }

        // Play audio
        await playAudio(audioData)
    }

    private func playAudio(_ data: Data) async {
        guard let playerNode = audioPlayerNode,
              let engine = audioEngine,
              let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
            isPlaying = false
            return
        }

        // Convert raw PCM data to audio buffer
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            isPlaying = false
            return
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            memcpy(buffer.audioBufferList.pointee.mBuffers.mData, baseAddress, data.count)
        }

        // Play the buffer
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("[TTS] Engine start error: \(error)")
                isPlaying = false
                return
            }
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                print("[TTS] Playback complete")
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        // Wait for playback to finish
        while playerNode.isPlaying {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }

        isPlaying = false
    }

    // MARK: - Stop

    func stop() {
        audioPlayerNode?.stop()
        isPlaying = false
        print("[TTS] Stopped")
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case apiError

    var errorDescription: String? {
        switch self {
        case .apiError:
            return "TTS API request failed"
        }
    }
}
