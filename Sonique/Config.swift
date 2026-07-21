import Foundation

enum Config {
    /// ElevenLabs API key for STT/TTS streaming
    /// Cached locally with expiration tracking. Fetched from SoniqueBar at runtime.
    private static var _cachedAPIKey: String?
    private static var _apiKeyFetchTime: Date?
    private static let apiKeyCacheTTL: TimeInterval = 3600  // 1 hour

    static func getAPIKey() async throws -> String {
        // Return cached key if available and not expired
        if let cached = _cachedAPIKey, let fetchTime = _apiKeyFetchTime {
            let elapsed = Date().timeIntervalSince(fetchTime)
            if elapsed < apiKeyCacheTTL {
                return cached
            }
        }

        // Fetch from SoniqueBar /config endpoint using the active (working) endpoint
        let baseURL = HTTPClient.activeBaseURL ?? commandServerURL
        guard let url = URL(string: "\(baseURL)/config") else {
            throw ConfigError.invalidURL
        }

        // Create request with auth token from iCloud preferences
        var request = URLRequest(url: url)
        let authToken = await MainActor.run { SoniqueBrain.shared.loadPreferences().authToken }
        if let token = authToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConfigError.serverError
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apiKey = json["elevenlabsAPIKey"] as? String else {
            throw ConfigError.invalidResponse
        }

        _cachedAPIKey = apiKey
        _apiKeyFetchTime = Date()
        return apiKey
    }

    /// Invalidate cached API key to force refetch on next use
    static func invalidateAPIKey() {
        _cachedAPIKey = nil
        _apiKeyFetchTime = nil
    }

    enum ConfigError: Error {
        case invalidURL
        case serverError
        case invalidResponse
    }

    // MARK: - SoniqueBar endpoints (user-configurable, iCloud-backed)

    // Defaults used only if Bonjour discovery fails
    static let defaultLANURL = "http://192.168.68.78:8890"  // Mac Mini M4 Pro (SoniqueBar CommandServer)
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
        // Extract host from URL like "http://192.168.68.78:8890" -> "192.168.68.78"
        // Falls back to first endpoint in endpointsToTry if parsing fails
        if let url = URL(string: commandServerURL), let host = url.host() {
            return host
        }
        // Fall back to primary endpoint host
        if let url = URL(string: defaultLANURL), let host = url.host() {
            return host
        }
        // Last resort fallback
        return "192.168.68.78"  // Default Mac Mini LAN address
    }
}
