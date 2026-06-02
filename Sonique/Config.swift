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
    /// Try LAN first for lower latency, fall back to Tailscale
    static var commandServerURL: String {
        // TODO: Add reachability check for LAN vs Tailscale
        // For now, prefer LAN when at home
        return "http://192.168.0.221:8890"
    }

    /// Tailscale fallback URL
    static let tailscaleURL = "http://100.122.13.35:8890"

    /// UserDefaults key for selected voice
    static let voiceKey = "selectedVoice"

    /// Get selected voice from UserDefaults
    static var selectedVoice: ElevenLabsVoice {
        get {
            if let raw = UserDefaults.standard.string(forKey: voiceKey),
               let voice = ElevenLabsVoice(rawValue: raw) {
                return voice
            }
            return .josh  // Default
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: voiceKey)
        }
    }
}
