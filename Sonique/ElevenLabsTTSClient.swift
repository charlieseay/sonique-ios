import Foundation

/// Fetches TTS audio from ElevenLabs as raw 24kHz mono 16-bit PCM.
/// Playback is handled by VoiceSession's shared AVAudioEngine (for echo cancellation),
/// so this type owns no audio engine of its own.
@MainActor
class ElevenLabsTTSClient: ObservableObject {
    private let apiKey: String
    private var currentTask: URLSessionDataTask?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Cancel any in-progress TTS fetch
    func cancelCurrentFetch() {
        currentTask?.cancel()
        currentTask = nil
        FileTracer.log("[tts] fetch cancelled")
    }

    /// Returns raw PCM (pcm_24000, 16-bit LE mono) for the given text, or nil on failure.
    func fetchPCM(_ text: String, voiceID: String) async -> Data? {
        guard !text.isEmpty else { return nil }
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream?output_format=pcm_24000")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_turbo_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ])

        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                Task { @MainActor in
                    self.currentTask = nil

                    if let error = error {
                        FileTracer.log("[tts] fetch failed: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let data = data,
                          let http = response as? HTTPURLResponse,
                          http.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        FileTracer.log("[tts] API error \(code)")
                        continuation.resume(returning: nil)
                        return
                    }

                    FileTracer.log("[tts] fetched \(data.count) PCM bytes for '\(text.prefix(30))'")
                    continuation.resume(returning: data)
                }
            }

            currentTask = task
            task.resume()
        }
    }
}
