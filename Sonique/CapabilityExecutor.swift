import Foundation
import SwiftUI
import MessageUI

/// Parses voice commands and executes native iOS capabilities
@MainActor
class CapabilityExecutor: ObservableObject {
    static let shared = CapabilityExecutor()

    private let capabilities = NativeCapabilities.shared
    @Published var showMessageComposer = false
    @Published var showMailComposer = false
    @Published var messageRecipient = ""
    @Published var messageBody = ""
    @Published var mailRecipient = ""
    @Published var mailSubject = ""
    @Published var mailBody = ""

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
            // Parse: "create event [title] at [time]"
            // For now, simple implementation
            if let title = extractBetween(lowercased, start: "event ", end: " at") {
                let date = Date().addingTimeInterval(3600) // 1 hour from now
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
            // Parse: "remind me to [task]"
            if let task = extractAfter(lowercased, after: "remind me to ") {
                let success = await capabilities.createReminder(title: task)
                return success ? "Reminder created: \(task)" : "Failed to create reminder"
            }
            return "I couldn't parse the reminder"
        }

        // Messages
        if lowercased.contains("send a message") || lowercased.contains("text") {
            // Parse: "send a message to [contact] saying [body]"
            // For now, extract basics and present composer
            if let recipient = extractBetween(lowercased, start: "to ", end: " saying"),
               let body = extractAfter(lowercased, after: "saying ") {

                if capabilities.canSendMessages {
                    messageRecipient = recipient
                    messageBody = body
                    showMessageComposer = true
                    return "Opening message composer"
                } else {
                    return "Messages are not available on this device"
                }
            }
            return "I couldn't parse the message details"
        }

        // Mail
        if lowercased.contains("send an email") || lowercased.contains("email") {
            // Parse: "send an email to [recipient] about [subject] saying [body]"
            if let recipient = extractBetween(lowercased, start: "to ", end: " about"),
               let subject = extractBetween(lowercased, start: "about ", end: " saying"),
               let body = extractAfter(lowercased, after: "saying ") {

                if capabilities.canSendMail {
                    mailRecipient = recipient
                    mailSubject = subject
                    mailBody = body
                    showMailComposer = true
                    return "Opening mail composer"
                } else {
                    return "Mail is not configured on this device"
                }
            }
            return "I couldn't parse the email details"
        }

        // Apple Intelligence (iOS 18.1+)
        if lowercased.contains("summarize") || lowercased.contains("writing tools") ||
           lowercased.contains("generate image") || lowercased.contains("image playground") {
            if AppleIntelligenceCompatibility.isAvailable {
                return await executeAppleIntelligence(command)
            } else {
                return "Apple Intelligence requires iOS 18.1 or later and a compatible device"
            }
        }

        return "I don't recognize that native capability command"
    }

    // MARK: - Apple Intelligence (iOS 18.1+)

    private func executeAppleIntelligence(_ command: String) async -> String {
        let lowercased = command.lowercased()

        // Summarize text
        if lowercased.contains("summarize") {
            if let text = extractAfter(lowercased, after: "summarize ") {
                return await AppleIntelligenceCompatibility.summarizeText(text)
            }
            return "What would you like me to summarize?"
        }

        // Generate image
        if lowercased.contains("generate image") || lowercased.contains("create image") {
            if let prompt = extractAfter(lowercased, after: "image ") {
                return await AppleIntelligenceCompatibility.generateImage(prompt: prompt)
            }
            return "What image would you like me to create?"
        }

        return "I can help you with Writing Tools and Image Playground via system features"
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
