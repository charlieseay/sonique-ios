import Foundation

enum Config {
    /// ElevenLabs API key for STT/TTS streaming
    /// Fetched from SoniqueBar at runtime
    private static var _cachedAPIKey: String?

    static func getAPIKey() async throws -> String {
        // Return cached key if available
        if let cached = _cachedAPIKey {
            return cached
        }

        // Fetch from SoniqueBar /config endpoint
        guard let url = URL(string: "\(commandServerURL)/config") else {
            throw ConfigError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConfigError.serverError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = json["elevenlabsAPIKey"] as? String else {
            throw ConfigError.invalidResponse
        }

        _cachedAPIKey = apiKey
        return apiKey
    }

    enum ConfigError: Error {
        case invalidURL
        case serverError
        case invalidResponse
    }

    /// SoniqueBar command server endpoint
    /// Reads from UserDefaults (configurable in Settings)
    static var commandServerURL: String {
        UserDefaults.standard.string(forKey: "serverURL") ?? "http://192.168.0.221:8890"
    }

    /// Tailscale fallback URL
    static let tailscaleURL = "http://100.122.13.35:8890"

    /// UserDefaults key for selected voice
    static let voiceKey = "selectedVoice"
    static let voiceNameKey = "selectedVoiceName"

    /// Legacy enum-based selection (kept for the playback path).
    static var selectedVoice: ElevenLabsVoice {
        get {
            if let raw = UserDefaults.standard.string(forKey: voiceKey),
               let voice = ElevenLabsVoice(rawValue: raw) {
                return voice
            }
            return .josh
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: voiceKey) }
    }

    /// Active voice ID (string) — set by the dynamic picker. Falls back to the enum.
    static var selectedVoiceID: String {
        get { UserDefaults.standard.string(forKey: voiceKey) ?? ElevenLabsVoice.adam.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: voiceKey) }
    }

    static var selectedVoiceName: String {
        get { UserDefaults.standard.string(forKey: voiceNameKey) ?? "Adam" }
        set { UserDefaults.standard.set(newValue, forKey: voiceNameKey) }
    }
}
