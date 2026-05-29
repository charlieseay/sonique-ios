import Foundation
import AVFoundation

/// ElevenLabs Conversational AI WebSocket client
/// Handles bidirectional audio: mic → STT → text, text → TTS → speaker
@MainActor
class ElevenLabsClient: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isListening = false
    @Published var lastTranscript = ""
    @Published var error: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?

    private let apiKey: String
    private var conversationID: String?

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        setupAudioEngine()
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let playerNode = audioPlayerNode else { return }

        engine.attach(playerNode)

        // Use standard format for playback
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)

        if let format = audioFormat {
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        }
    }

    // MARK: - Connection

    func connect() {
        guard webSocketTask == nil else { return }

        // Use Conversational AI endpoint with selected voice
        let voiceID = Config.selectedVoice.rawValue
        let urlString = "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=\(voiceID)"

        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()

        isConnected = true
        print("[ElevenLabs] Connected to Conversational AI")
    }

    func disconnect() {
        stopListening()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("[ElevenLabs] Disconnected")
    }

    // MARK: - Audio Streaming

    func startListening() {
        guard isConnected else { return }
        guard let engine = audioEngine else { return }

        do {
            // Start audio engine for playback
            if !engine.isRunning {
                try engine.start()
            }
            audioPlayerNode?.play()

            isListening = true
            print("[ElevenLabs] Started listening")
        } catch {
            self.error = "Audio engine failed: \(error.localizedDescription)"
            print("[ElevenLabs] Audio engine error: \(error)")
        }
    }

    func stopListening() {
        audioPlayerNode?.stop()
        audioEngine?.stop()
        isListening = false
        print("[ElevenLabs] Stopped listening")
    }

    func sendText(_ text: String) {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "text_input",
            "text": text
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("[ElevenLabs] Send error: \(error)")
            } else {
                print("[ElevenLabs] Sent: \(text)")
            }
        }
    }

    // MARK: - WebSocket Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                Task { @MainActor in
                    await self.handleMessage(message)
                }
                self.receiveMessage()

            case .failure(let error):
                Task { @MainActor in
                    self.error = error.localizedDescription
                    self.isConnected = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            // Parse JSON response
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let type = json["type"] as? String {
                switch type {
                case "conversation_initiation_metadata":
                    if let convID = json["conversation_id"] as? String {
                        conversationID = convID
                        print("[ElevenLabs] Conversation ID: \(convID)")
                    }

                case "user_transcript":
                    if let transcript = json["user_transcript"] as? String {
                        lastTranscript = transcript
                        print("[ElevenLabs] User said: \(transcript)")

                        // Notify VoiceLoop
                        NotificationCenter.default.post(name: .elevenLabsTranscript, object: nil)
                    }

                case "audio":
                    // Audio response from AI
                    if let audioBase64 = json["audio_event"] as? String {
                        await playAudioChunk(base64: audioBase64)
                    }

                default:
                    print("[ElevenLabs] Unknown type: \(type)")
                }
            }

        case .data(let data):
            // Binary audio data (PCM)
            await playAudioData(data)

        @unknown default:
            break
        }
    }

    // MARK: - Audio Playback

    private func playAudioChunk(base64: String) async {
        guard let audioData = Data(base64Encoded: base64) else { return }
        await playAudioData(audioData)
    }

    private func playAudioData(_ data: Data) async {
        guard let playerNode = audioPlayerNode,
              let format = audioFormat else { return }

        // Convert data to PCM buffer
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            memcpy(buffer.audioBufferList.pointee.mBuffers.mData, baseAddress, data.count)
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ElevenLabsClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            print("[ElevenLabs] WebSocket opened")
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            isConnected = false
            print("[ElevenLabs] WebSocket closed")
        }
    }
}
