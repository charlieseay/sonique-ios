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

        // Fetch from SoniqueBar /config endpoint using the active (working) endpoint
        let baseURL = HTTPClient.activeBaseURL ?? commandServerURL
        guard let url = URL(string: "\(baseURL)/config") else {
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

    // MARK: - SoniqueBar endpoints (user-configurable, iCloud-backed)

    // Defaults used only if Bonjour discovery fails
    static let defaultLANURL = "http://192.168.68.78:8890"  // Fallback only
    static let defaultTailscaleURL = "http://100.122.13.35:8890"  // SoniqueBar via Tailscale

    @MainActor
    private static var prefs: SoniqueBrain.Preferences {
        get { SoniqueBrain.shared.loadPreferences() }
        set { SoniqueBrain.shared.savePreferences(newValue) }
    }

    /// Primary endpoint (LAN by default). User-editable in Settings.
    static var commandServerURL: String {
        get {
            Task { @MainActor in
                prefs.serverURL ?? defaultLANURL
            }
            // Synchronous fallback for non-async contexts
            return UserDefaults.standard.string(forKey: "serverURL") ?? defaultLANURL
        }
        set {
            Task { @MainActor in
                var p = prefs
                p.serverURL = newValue
                prefs = p
            }
            UserDefaults.standard.set(newValue, forKey: "serverURL")  // Ephemeral cache
        }
    }

    /// Tailscale endpoint — used as a fallback so Sonique works anywhere, not just LAN.
    static var tailscaleURL: String {
        get {
            Task { @MainActor in
                prefs.tailscaleURL ?? defaultTailscaleURL
            }
            return UserDefaults.standard.string(forKey: "tailscaleURL") ?? defaultTailscaleURL
        }
        set {
            Task { @MainActor in
                var p = prefs
                p.tailscaleURL = newValue
                prefs = p
            }
            UserDefaults.standard.set(newValue, forKey: "tailscaleURL")
        }
    }

    /// Whether to fall back to the Tailscale endpoint when the primary is unreachable.
    static var tailscaleFallbackEnabled: Bool {
        get {
            Task { @MainActor in
                prefs.tailscaleFallbackEnabled ?? true
            }
            return UserDefaults.standard.object(forKey: "tailscaleFallback") as? Bool ?? true
        }
        set {
            Task { @MainActor in
                var p = prefs
                p.tailscaleFallbackEnabled = newValue
                prefs = p
            }
            UserDefaults.standard.set(newValue, forKey: "tailscaleFallback")
        }
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
        get {
            Task { @MainActor in
                prefs.selectedVoiceID ?? ElevenLabsVoice.adam.rawValue
            }
            return UserDefaults.standard.string(forKey: voiceKey) ?? ElevenLabsVoice.adam.rawValue
        }
        set {
            Task { @MainActor in
                var p = prefs
                p.selectedVoiceID = newValue
                prefs = p
            }
            UserDefaults.standard.set(newValue, forKey: voiceKey)
        }
    }

    static var selectedVoiceName: String {
        get {
            Task { @MainActor in
                prefs.selectedVoiceName ?? "Adam"
            }
            return UserDefaults.standard.string(forKey: voiceNameKey) ?? "Adam"
        }
        set {
            Task { @MainActor in
                var p = prefs
                p.selectedVoiceName = newValue
                prefs = p
            }
            UserDefaults.standard.set(newValue, forKey: voiceNameKey)
        }
    }

    /// Extract host from commandServerURL for TTS client
    static var soniqueBarHost: String {
        // Extract host from URL like "http://192.168.0.221:8890" -> "192.168.0.221"
        if let url = URL(string: commandServerURL) {
            return url.host() ?? "192.168.0.221"
        }
        // Last resort: default LAN IP
        return "192.168.0.221"
    }
}
