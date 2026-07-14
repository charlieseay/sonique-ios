import Foundation

/// Parses voice commands and executes native iOS capabilities.
/// Returns nil when no capability matches (caller should fall through to SoniqueBar).
@MainActor
class CapabilityExecutor {
    static let shared = CapabilityExecutor()
    private let capabilities = NativeCapabilities.shared
    private init() {}

    func execute(_ command: String) async -> String? {
        let q = command.lowercased()

        // Calendar — read
        if q.contains("what's on my calendar") || q.contains("events today") {
            let events = await capabilities.getTodayEvents()
            return events.isEmpty ? "You have no events today." : "Today's events: \(events.joined(separator: ", "))."
        }

        // Calendar — create
        if q.contains("create") && q.contains("event"), let title = extractBetween(q, start: "event ", end: " at") {
            let success = await capabilities.createCalendarEvent(title: title, date: Date().addingTimeInterval(3600))
            return success ? "Created event: \(title)." : "Failed to create the event."
        }

        // Reminders — read
        if q.contains("what are my reminders") || q.contains("list reminders") {
            let items = await capabilities.getReminders()
            return items.isEmpty ? "You have no reminders." : "Reminders: \(items.joined(separator: ", "))."
        }

        // Reminders — create
        if q.contains("remind me to"), let task = extractAfter(q, after: "remind me to ") {
            let success = await capabilities.createReminder(title: task)
            return success ? "Reminder created: \(task)." : "Failed to create the reminder."
        }

        return nil
    }

    // MARK: - Helpers

    private func extractBetween(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else { return nil }
        return String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private func extractAfter(_ text: String, after: String) -> String? {
        guard let range = text.range(of: after) else { return nil }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
