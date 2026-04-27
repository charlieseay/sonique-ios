import AppIntents
import Foundation
import EventKit

// MARK: - Calendar Reading Intent

struct ReadCalendarEventsIntent: AppIntent {
    static var title: LocalizedStringResource = "Read upcoming calendar events"
    static var description = IntentDescription(
        "Get your upcoming calendar events for the next week.",
        categoryName: "Calendar"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Days ahead", default: 7)
    var daysAhead: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = CalendarService.shared
        let hasAccess = await calendar.requestAccess()

        guard hasAccess else {
            return .result(dialog: IntentDialog(stringLiteral: "Calendar access denied. Enable it in Settings."))
        }

        let events = await calendar.fetchUpcomingEvents(daysAhead: daysAhead)

        guard !events.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No upcoming events."))
        }

        let eventSummary = events.prefix(5).map { event in
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            let timeStr = timeFormatter.string(from: event.startDate)
            return "\(event.title) at \(timeStr)"
        }.joined(separator: ", ")

        return .result(dialog: IntentDialog(stringLiteral: "Your next events: \(eventSummary)"))
    }
}

// MARK: - Calendar Creating Intent

struct CreateCalendarEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Create calendar event"
    static var description = IntentDescription(
        "Add a new event to your calendar.",
        categoryName: "Calendar"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Event title")
    var eventTitle: String

    @Parameter(title: "Date and time")
    var eventDate: Date

    @Parameter(title: "Duration in minutes", default: 60)
    var durationMinutes: Int

    @Parameter(title: "Description")
    var eventDescription: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let calendar = CalendarService.shared
        let hasAccess = await calendar.requestAccess()

        guard hasAccess else {
            return .result(dialog: IntentDialog(stringLiteral: "Calendar access denied."))
        }

        let startDate = eventDate
        let endDate = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startDate) ?? startDate

        do {
            try await calendar.createEvent(
                title: eventTitle,
                description: eventDescription,
                startDate: startDate,
                endDate: endDate
            )
            return .result(dialog: IntentDialog(stringLiteral: "Event '\(eventTitle)' created."))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "Failed to create event."))
        }
    }
}
