import Foundation
import AVFoundation

struct CatalogVoice: Identifiable, Equatable {
    let id: String          // voice_id
    let name: String        // "Adam - Dominant, Firm" → split for display
    let previewURL: String
    let category: String

    var displayName: String { name.components(separatedBy: " - ").first ?? name }
    var descriptor: String {
        let parts = name.components(separatedBy: " - ")
        return parts.count > 1 ? parts[1] : ""
    }
}

/// Fetches the ElevenLabs voice catalog and plays preview samples (Claude/Gemini-style
/// sample-before-select). Previews stream from ElevenLabs' preview_url (MP3) via AVPlayer,
/// so nothing is "downloaded" permanently — just a quick listen.
@MainActor
class VoiceCatalog: NSObject, ObservableObject {
    @Published var voices: [CatalogVoice] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var sampling: String?   // voice_id currently previewing

    private var previewPlayer: AVPlayer?
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    func load() async {
        guard voices.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = json["voices"] as? [[String: Any]] else {
                error = "Couldn't load voices"
                return
            }
            voices = arr.compactMap { v in
                guard let id = v["voice_id"] as? String,
                      let name = v["name"] as? String,
                      let preview = v["preview_url"] as? String, !preview.isEmpty else { return nil }
                return CatalogVoice(id: id, name: name, previewURL: preview,
                                    category: v["category"] as? String ?? "premade")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stream and play a voice's preview sample. Tapping another stops the current one.
    func playSample(_ voice: CatalogVoice) {
        // Use a playback session that won't fight the main voice loop (we're in Settings).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? session.setActive(true)

        previewPlayer?.pause()
        guard let url = URL(string: voice.previewURL) else { return }
        let item = AVPlayerItem(url: url)
        NotificationCenter.default.addObserver(self, selector: #selector(sampleFinished),
                                               name: .AVPlayerItemDidPlayToEndTime, object: item)
        previewPlayer = AVPlayer(playerItem: item)
        sampling = voice.id
        previewPlayer?.play()
    }

    @objc private func sampleFinished() {
        sampling = nil
    }

    func stopSample() {
        previewPlayer?.pause()
        previewPlayer = nil
        sampling = nil
    }
}
