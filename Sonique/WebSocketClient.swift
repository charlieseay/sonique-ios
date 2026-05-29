import Foundation
import AVFoundation

/// ElevenLabs WebSocket client for streaming STT/TTS
/// Handles bidirectional audio: mic → STT → text, text → TTS → speaker
@MainActor
class ElevenLabsClient: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isListening = false
    @Published var lastTranscript = ""
    @Published var error: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayer?

    private let apiKey: String
    private var voiceID: String
    private var hasReceivedGreeting = false

    init(apiKey: String, voiceID: String = Config.selectedVoice.rawValue) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        super.init()
    }

    // MARK: - Connection

    func connect() {
        guard webSocketTask == nil else { return }

        // Use selected voice ID
        self.voiceID = Config.selectedVoice.rawValue
        hasReceivedGreeting = false

        var request = URLRequest(url: URL(string: "wss://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream-input?model_id=eleven_turbo_v2")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveMessage()

        isConnected = true
        print("[ElevenLabs] Connected")
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("[ElevenLabs] Disconnected")
    }

    // MARK: - Audio Streaming

    func startListening() {
        guard isConnected else { return }

        // TODO: Start audio engine, capture mic, send PCM chunks via WebSocket
        isListening = true
        print("[ElevenLabs] Started listening")
    }

    func stopListening() {
        isListening = false
        print("[ElevenLabs] Stopped listening")
    }

    func sendText(_ text: String) {
        guard isConnected else { return }

        // Send text message to trigger TTS response
        let message = ["type": "text", "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }

        webSocketTask?.send(.string(String(data: data, encoding: .utf8)!)) { error in
            if let error = error {
                print("[ElevenLabs] Send error: \(error)")
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
                    self.handleMessage(message)
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

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Parse JSON response
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            if type == "transcript" {
                if let transcript = json["text"] as? String {
                    // Skip the greeting
                    if !hasReceivedGreeting && transcript.contains("I'm Cael") {
                        hasReceivedGreeting = true
                        print("[ElevenLabs] Skipped greeting")
                        return
                    }

                    lastTranscript = transcript
                    print("[ElevenLabs] Transcript: \(transcript)")

                    // Notify VoiceLoop
                    NotificationCenter.default.post(name: .elevenLabsTranscript, object: nil)
                }
            } else if type == "audio" {
                // Skip audio for greeting
                if !hasReceivedGreeting {
                    hasReceivedGreeting = true
                    print("[ElevenLabs] Skipped greeting audio")
                    return
                }
                // TODO: Decode base64 audio and play via AVAudioPlayer
                print("[ElevenLabs] Received audio chunk")
            }

        case .data(let data):
            // Binary audio data
            print("[ElevenLabs] Received binary audio: \(data.count) bytes")

        @unknown default:
            break
        }
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
