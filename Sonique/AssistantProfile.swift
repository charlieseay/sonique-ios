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
