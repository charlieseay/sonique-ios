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

    private init() { ensureStructure() }

    /// iCloud base via this app's ubiquity container's Documents folder. Requires the
    /// iCloud Documents entitlement; nil if unavailable (→ local fallback). When the
    /// entitlement is added, this syncs to iCloud Drive under the app's folder.
    private var iCloudBase: URL? {
        guard let container = fm.url(forUbiquityContainerIdentifier: nil) else { return nil }
        return container.appendingPathComponent("Documents/SoniqueProfiles")
    }

    private var localFallback: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SoniqueProfiles")
    }

    private var base: URL { iCloudBase ?? localFallback }
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
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func appendJSONL(_ obj: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let line = String(data: data, encoding: .utf8) else { return }
        let entry = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let d = entry.data(using: .utf8) { handle.write(d) }
            try? handle.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
