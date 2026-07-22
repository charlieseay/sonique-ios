import Foundation
import Intents
import EventKit

/// Manages execution of iOS Shortcuts and system intents
/// Enables Quinn to actually DO things (set timers, toggle DND, create reminders)
@MainActor
class ShortcutsManager: NSObject {
    static let shared = ShortcutsManager()

    private let eventStore = EKEventStore()

    override private init() {
        super.init()
    }

    // MARK: - Timer Management

    /// Set a timer for the specified duration
    func setTimer(minutes: Int) async -> Result<String, ShortcutError> {
        // iOS doesn't have a direct Timer API via Intents
        // Use INSetTimerIntent (iOS 13+)
        let intent = INSetTimerIntent()
        intent.duration = Double(minutes * 60)
        intent.label = INSpeakableString(spokenPhrase: "Voice timer")

        do {
            let interaction = INInteraction(intent: intent, response: nil)
            try await interaction.donate()

            FileTracer.log("[shortcuts] Timer set for \(minutes) minutes")
            return .success("Timer set for \(minutes) minute\(minutes == 1 ? "" : "s")")
        } catch {
            FileTracer.log("[shortcuts] Failed to set timer: \(error)")
            return .failure(.executionFailed("Couldn't set timer: \(error.localizedDescription)"))
        }
    }

    // MARK: - Do Not Disturb

    /// Toggle Do Not Disturb mode
    /// Note: iOS doesn't provide API for DND control - requires Shortcuts app integration
    func toggleDoNotDisturb(enable: Bool) async -> Result<String, ShortcutError> {
        // This requires user to create a Shortcut named "Enable DND" or "Disable DND"
        // We can trigger it via x-callback-url
        let shortcutName = enable ? "Enable DND" : "Disable DND"
        let urlString = "shortcuts://run-shortcut?name=\(shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        guard let url = URL(string: urlString) else {
            return .failure(.invalidParameters("Invalid shortcut URL"))
        }

        // Open the shortcut
        if await UIApplication.shared.open(url) {
            FileTracer.log("[shortcuts] DND toggled: \(enable)")
            return .success("Do Not Disturb \(enable ? "enabled" : "disabled")")
        } else {
            return .failure(.shortcutNotFound("Couldn't find DND shortcut - please create '\(shortcutName)' in Shortcuts app"))
        }
    }

    // MARK: - Reminders

    /// Create a reminder
    func createReminder(title: String, dueDate: Date? = nil) async -> Result<String, ShortcutError> {
        // Request permission if needed
        let status = EKEventStore.authorizationStatus(for: .reminder)

        if status == .notDetermined {
            let granted = try? await eventStore.requestAccess(to: .reminder)
            if granted != true {
                return .failure(.permissionDenied("Need reminders permission"))
            }
        } else if status != .authorized {
            return .failure(.permissionDenied("Reminders permission denied - enable in Settings"))
        }

        // Create reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dueDate = dueDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        }

        do {
            try eventStore.save(reminder, commit: true)
            FileTracer.log("[shortcuts] Reminder created: \(title)")

            let dueDateStr = dueDate.map { " for \(formatDate($0))" } ?? ""
            return .success("Reminder created\(dueDateStr)")
        } catch {
            FileTracer.log("[shortcuts] Failed to create reminder: \(error)")
            return .failure(.executionFailed("Couldn't create reminder: \(error.localizedDescription)"))
        }
    }

    // MARK: - Shortcut Execution (Generic)

    /// Execute a named shortcut created in Shortcuts app
    func runShortcut(named name: String, parameters: [String: Any] = [:]) async -> Result<String, ShortcutError> {
        var urlComponents = URLComponents(string: "shortcuts://run-shortcut")!
        urlComponents.queryItems = [
            URLQueryItem(name: "name", value: name)
        ]

        // Add parameters as input
        if !parameters.isEmpty, let jsonData = try? JSONSerialization.data(withJSONObject: parameters),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            urlComponents.queryItems?.append(URLQueryItem(name: "input", value: jsonString))
        }

        guard let url = urlComponents.url else {
            return .failure(.invalidParameters("Invalid shortcut URL"))
        }

        if await UIApplication.shared.open(url) {
            FileTracer.log("[shortcuts] Executed shortcut: \(name)")
            return .success("Ran \(name)")
        } else {
            return .failure(.shortcutNotFound("Couldn't find shortcut '\(name)' - create it in Shortcuts app"))
        }
    }

    // MARK: - Capability Discovery

    /// List shortcuts that Quinn knows how to execute
    func listCapabilities() -> [ShortcutCapability] {
        return [
            ShortcutCapability(
                name: "Set Timer",
                patterns: ["set timer for", "timer for", "set a timer"],
                requiresPermission: false
            ),
            ShortcutCapability(
                name: "Toggle Do Not Disturb",
                patterns: ["turn on do not disturb", "enable dnd", "turn off do not disturb", "disable dnd"],
                requiresPermission: false,
                requiresSetup: "Create 'Enable DND' and 'Disable DND' shortcuts in Shortcuts app"
            ),
            ShortcutCapability(
                name: "Create Reminder",
                patterns: ["remind me to", "create reminder", "add reminder"],
                requiresPermission: true,
                permissionType: "Reminders"
            )
        ]
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Types

enum ShortcutError: LocalizedError {
    case permissionDenied(String)
    case shortcutNotFound(String)
    case invalidParameters(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let msg),
             .shortcutNotFound(let msg),
             .invalidParameters(let msg),
             .executionFailed(let msg):
            return msg
        }
    }
}

struct ShortcutCapability {
    let name: String
    let patterns: [String]
    let requiresPermission: Bool
    let permissionType: String?
    let requiresSetup: String?

    init(name: String, patterns: [String], requiresPermission: Bool, permissionType: String? = nil, requiresSetup: String? = nil) {
        self.name = name
        self.patterns = patterns
        self.requiresPermission = requiresPermission
        self.permissionType = permissionType
        self.requiresSetup = requiresSetup
    }
}
