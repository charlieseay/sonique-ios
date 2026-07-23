import Foundation

/// iOS side of the iCloud-backed brain. Reads the SHARED persona (written by SoniqueBar)
/// and the mobile directives overlay; writes this device's lessons + conversations to the
/// `mobile/` folder. Mirrors SoniqueBar's SoniqueBrain.
///
///   iCloud Drive/SoniqueProfiles/
///     shared/   IDENTITY.md, RULES.md, SOUL.md   (read)
///     mobile/   lessons.jsonl, directives.md, conversations.jsonl   (this device owns)
@MainActor
final class SoniqueBrain {
    static let shared = SoniqueBrain()

    var quotaBytes: Int = 30 * 1024 * 1024   // 30 MB on mobile
    private let device = "mobile"
    private let fm = FileManager.default

    private let containerID = "iCloud.com.seayniclabs.sonique"
    private var cachedBase: URL?

    private init() {
        ensureStructure()  // local fallback immediately
        // Resolve the shared ubiquity container OFF the main thread (Apple: it can block).
        let id = containerID
        let fmRef = fm
        Task.detached(priority: .utility) {
            let resolved = fmRef.url(forUbiquityContainerIdentifier: id)?
                .appendingPathComponent("Documents/SoniqueProfiles")
            await MainActor.run {
                self.cachedBase = resolved
                self.ensureStructure()
            }
        }
    }

    private var localFallback: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoniqueProfiles")
    }

    private var base: URL { cachedBase ?? localFallback }
    private var sharedDir: URL { base.appendingPathComponent("shared") }
    private var deviceDir: URL { base.appendingPathComponent(device) }

    private func ensureStructure() {
        for dir in [sharedDir, deviceDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reads

    /// Shared persona + mobile directives + recent mobile lessons, for relaying to SoniqueBar
    /// (so the Mac LLM has the device's context too, if we ever want to pass it).
    func personaContext() -> String {
        let identity = readText(sharedDir.appendingPathComponent("IDENTITY.md"))
        let directives = readText(deviceDir.appendingPathComponent("directives.md"))
        var parts: [String] = []
        if !identity.isEmpty { parts.append("# Identity\n\(identity)") }
        if !directives.isEmpty { parts.append("# Mobile Directives\n\(directives)") }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Reads (Conversation History)

    /// Get recent conversation history for context
    func getRecentConversations(limit: Int = 10) -> [[String: String]] {
        let conversationsURL = deviceDir.appendingPathComponent("conversations.jsonl")
        let text = readText(conversationsURL)
        guard !text.isEmpty else { return [] }

        var exchanges: [[String: String]] = []
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Take last N lines (most recent)
        let recentLines = lines.suffix(limit)

        for line in recentLines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["user"] as? String,
                  let assistant = json["assistant"] as? String else {
                continue
            }
            exchanges.append(["user": user, "assistant": assistant])
        }

        return exchanges
    }

    // MARK: - Writes

    func recordExchange(user: String, assistant: String) {
        let entry: [String: Any] = [
            "user": user, "assistant": assistant,
            "ts": ISO8601DateFormatter().string(from: Date())
        ]
        appendJSONL(entry, to: deviceDir.appendingPathComponent("conversations.jsonl"))
        enforceQuota()
    }

    func recordLesson(_ text: String) {
        let entry: [String: Any] = ["lesson": text, "ts": ISO8601DateFormatter().string(from: Date())]
        appendJSONL(entry, to: deviceDir.appendingPathComponent("lessons.jsonl"))
        enforceQuota()
    }

    // MARK: - Preferences (iCloud-backed, survives reinstalls)

    private var prefsURL: URL { deviceDir.appendingPathComponent("preferences.json") }
    private var sharedPrefsURL: URL { sharedDir.appendingPathComponent("preferences.json") }

    /// Load SHARED preferences (written by SoniqueBar, contains serverURL + authToken)
    func loadSharedPreferences() -> Preferences {
        let text = readText(sharedPrefsURL)
        if !text.isEmpty,
           let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            return decoded
        }
        return Preferences()
    }

    struct Preferences: Codable {
        var serverURL: String?
        var tailscaleURL: String?
        var tailscaleFallbackEnabled: Bool?
        var selectedVoiceID: String?
        var selectedVoiceName: String?
        var authToken: String?  // Bearer token for CommandServer authentication
        var permissionsGranted: PermissionState?
        var discoveredCapabilities: DiscoveredCapabilities?
        var lastCapabilityDiscovery: String?  // ISO8601 timestamp

        struct PermissionState: Codable {
            var speech: Bool
            var microphone: Bool
        }

        struct DiscoveredCapabilities: Codable {
            var homeKitDevices: [String]?  // List of HomeKit accessory names
            var mcpServers: [MCPServerInfo]?  // Available MCP servers
            var availableAPIs: [String]?  // Available web APIs
        }

        struct MCPServerInfo: Codable {
            var name: String
            var endpoint: String
            var capabilities: [String]
        }
    }

    func loadPreferences() -> Preferences {
        // Load mobile-specific preferences
        let text = readText(prefsURL)
        var prefs: Preferences
        if !text.isEmpty,
           let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = decoded
        } else {
            prefs = Preferences()
        }

        // Auth token comes from shared/ (written by macOS SoniqueBar)
        let sharedPrefsURL = sharedDir.appendingPathComponent("preferences.json")
        let sharedText = readText(sharedPrefsURL)
        if !sharedText.isEmpty,
           let sharedData = sharedText.data(using: .utf8),
           let sharedPrefs = try? JSONDecoder().decode(Preferences.self, from: sharedData),
           let authToken = sharedPrefs.authToken {
            prefs.authToken = authToken
        }

        return prefs
    }

    func savePreferences(_ prefs: Preferences) {
        guard let data = try? JSONEncoder().encode(prefs),
              let json = String(data: data, encoding: .utf8) else { return }

        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: prefsURL, options: [], error: &coordError) { writeURL in
            try? json.write(to: writeURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Quota

    private func enforceQuota() {
        guard deviceFolderSize() > quotaBytes else { return }
        trimOldest(deviceDir.appendingPathComponent("conversations.jsonl"), keepFraction: 0.7)
        if deviceFolderSize() > quotaBytes {
            trimOldest(deviceDir.appendingPathComponent("lessons.jsonl"), keepFraction: 0.8)
        }
    }

    private func deviceFolderSize() -> Int {
        guard let files = try? fm.contentsOfDirectory(at: deviceDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private func trimOldest(_ url: URL, keepFraction: Double) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        let keep = max(1, Int(Double(lines.count) * keepFraction))
        let trimmed = lines.suffix(keep).joined(separator: "\n") + "\n"
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private func readText(_ url: URL) -> String {
        // Trigger download for files another device wrote, then coordinated read.
        if (try? url.checkResourceIsReachable()) != true {
            try? fm.startDownloadingUbiquitousItem(at: url)
        }
        var result = ""
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            result = (try? String(contentsOf: readURL, encoding: .utf8)) ?? ""
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Coordinated append — safe when both devices touch the same file.
    private func appendJSONL(_ obj: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8) else { return }
        let entry = line + "\n"
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { writeURL in
            if let handle = try? FileHandle(forWritingTo: writeURL) {
                handle.seekToEndOfFile()
                if let d = entry.data(using: .utf8) { handle.write(d) }
                try? handle.close()
            } else {
                try? entry.write(to: writeURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
// Updated Fri Jul 17 13:56:30 CDT 2026
