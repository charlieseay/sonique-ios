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

    // MARK: - SoniqueBar endpoints (user-configurable)

    static let defaultLANURL = "http://192.168.0.221:8890"
    static let defaultTailscaleURL = "http://100.122.13.35:8890"  // SoniqueBar via Tailscale

    /// Primary endpoint (LAN by default). User-editable in Settings.
    static var commandServerURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? defaultLANURL }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    /// Tailscale endpoint — used as a fallback so Sonique works anywhere, not just LAN.
    static var tailscaleURL: String {
        get { UserDefaults.standard.string(forKey: "tailscaleURL") ?? defaultTailscaleURL }
        set { UserDefaults.standard.set(newValue, forKey: "tailscaleURL") }
    }

    /// Whether to fall back to the Tailscale endpoint when the primary is unreachable.
    static var tailscaleFallbackEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "tailscaleFallback") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "tailscaleFallback") }
    }

    /// Ordered endpoints to try: primary, then Tailscale (if enabled + distinct).
    static var endpointsToTry: [String] {
        var list = [commandServerURL]
        if tailscaleFallbackEnabled, !tailscaleURL.isEmpty, tailscaleURL != commandServerURL {
            list.append(tailscaleURL)
        }
        return list
    }

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
