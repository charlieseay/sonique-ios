import Foundation
import SwiftUI

/// Parses voice commands and executes native iOS capabilities
@MainActor
class CapabilityExecutor: ObservableObject {
    static let shared = CapabilityExecutor()

    private let capabilities = NativeCapabilities.shared

    private init() {}

    /// Execute a capability based on parsed command
    func execute(_ command: String) async -> String {
        let lowercased = command.lowercased()

        // Calendar
        if lowercased.contains("what's on my calendar") || lowercased.contains("events today") {
            let events = await capabilities.getTodayEvents()
            return events.isEmpty ? "You have no events today" : "Today's events: \(events.joined(separator: ", "))"
        }

        if lowercased.contains("create") && lowercased.contains("event") {
            if let title = extractBetween(lowercased, start: "event ", end: " at") {
                let date = Date().addingTimeInterval(3600)
                let success = await capabilities.createCalendarEvent(title: title, date: date)
                return success ? "Created event: \(title)" : "Failed to create event"
            }
            return "I couldn't parse the event details"
        }

        // Reminders
        if lowercased.contains("what are my reminders") || lowercased.contains("list reminders") {
            let reminders = await capabilities.getReminders()
            return reminders.isEmpty ? "You have no reminders" : "Reminders: \(reminders.joined(separator: ", "))"
        }

        if lowercased.contains("remind me to") {
            if let task = extractAfter(lowercased, after: "remind me to ") {
                let success = await capabilities.createReminder(title: task)
                return success ? "Reminder created: \(task)" : "Failed to create reminder"
            }
            return "I couldn't parse the reminder"
        }

        return "I don't recognize that native capability command"
    }

    // MARK: - String Parsing Helpers

    private func extractBetween(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private func extractAfter(_ text: String, after: String) -> String? {
        guard let range = text.range(of: after) else { return nil }
        return String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
