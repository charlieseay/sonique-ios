import Foundation
import SwiftUI

/// The user-configurable identity of the assistant: its name (default "Sonique",
/// which doubles as the wake word) and an optional profile photo. Persisted in the
/// iCloud brain's mobile/ folder (assistant.json + photo.jpg) with a UserDefaults
/// mirror so it's available instantly at launch.
@MainActor
final class AssistantProfile: ObservableObject {
    static let shared = AssistantProfile()

    @Published var name: String { didSet { persist() } }
    @Published var photo: UIImage? { didSet { persistPhoto() } }

    private let nameKey = "assistantName"
    private let fm = FileManager.default

    private init() {
        // 1) UserDefaults (instant) → 2) brain assistant.json → 3) default "Sonique"
        if let saved = UserDefaults.standard.string(forKey: nameKey), !saved.isEmpty {
            name = saved
        } else {
            name = AssistantProfile.readBrainName() ?? "Sonique"
        }
        photo = AssistantProfile.readBrainPhoto()
    }

    /// Lowercased wake word derived from the name (first word, e.g. "Cael").
    var wakeWord: String {
        name.lowercased().split(separator: " ").first.map(String.init) ?? name.lowercased()
    }

    /// Skills manifest - capabilities exposed to the LLM
    var skills: [[String: Any]] {
        [
            ["category": "Time & Calendar", "skills": [
                "Current time and date",
                "Calendar events and meetings",
                "Create/update calendar events"
            ]],
            ["category": "System Control", "skills": [
                "Open/close applications",
                "System volume control",
                "Display brightness",
                "Screenshot capture"
            ]],
            ["category": "Home Automation", "skills": [
                "Control lights (on/off, brightness, color)",
                "Query device status",
                "Scene activation",
                "HomeKit and Home Assistant integration"
            ]],
            ["category": "Knowledge & Memory", "skills": [
                "Search Obsidian vault notes",
                "Read/append to daily note",
                "Create new notes",
                "Query conversation history",
                "Team knowledge base access (NotebookLM)"
            ]],
            ["category": "Communication", "skills": [
                "Send Slack messages",
                "Read Slack channels",
                "Email composition (future)",
                "SMS/iMessage (future)"
            ]],
            ["category": "Infrastructure & DevOps", "skills": [
                "Check Docker container status",
                "Start/stop/restart containers",
                "View service logs",
                "Helmsman queue management",
                "Service health checks"
            ]],
            ["category": "Web & Research", "skills": [
                "Web search",
                "Fetch and summarize URLs",
                "Weather information",
                "General knowledge queries"
            ]],
            ["category": "Vision & Analysis", "skills": [
                "Analyze screenshots",
                "Describe images",
                "Visual question answering",
                "Camera capture (future)"
            ]],
            ["category": "File Operations", "skills": [
                "Find files",
                "List directory contents",
                "Read file contents",
                "File management (future)"
            ]]
        ]
    }

    /// Skills manifest as JSON string for HTTP payload
    var skillsJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: skills),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(name, forKey: nameKey)
        guard let dir = Self.mobileDir() else { return }
        let json: [String: Any] = ["name": name, "photo": photo != nil ? "photo.jpg" as Any : NSNull()]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            try? data.write(to: dir.appendingPathComponent("assistant.json"))
        }
    }

    private func persistPhoto() {
        guard let dir = Self.mobileDir() else { return }
        let url = dir.appendingPathComponent("photo.jpg")
        if let photo, let data = photo.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url)
        } else {
            try? fm.removeItem(at: url)
        }
        persist()
    }

    // MARK: - Brain location

    private static func mobileDir() -> URL? {
        let fm = FileManager.default
        let base: URL
        if let container = fm.url(forUbiquityContainerIdentifier: nil) {
            base = container.appendingPathComponent("Documents/SoniqueProfiles")
        } else {
            base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SoniqueProfiles")
        }
        let dir = base.appendingPathComponent("mobile")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func readBrainName() -> String? {
        guard let dir = mobileDir() else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("assistant.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    private static func readBrainPhoto() -> UIImage? {
        guard let dir = mobileDir() else { return nil }
        let url = dir.appendingPathComponent("photo.jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
