import Foundation
import EventKit

@MainActor
class CalendarService {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    // MARK: - Public API

    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                try await eventStore.requestFullAccessToEvents()
                return true
            } catch {
                return false
            }
        } else {
            // iOS 16 and earlier
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func fetchUpcomingEvents(daysAhead: Int = 7) async -> [EKEvent] {
        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? Date()

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate
        )

        return eventStore.events(matching: predicate)
    }

    func createEvent(
        title: String,
        description: String? = nil,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        calendar: EKCalendar? = nil
    ) async throws {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = description
        event.startDate = startDate
        event.endDate = endDate
        event.location = location
        event.calendar = calendar ?? eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)
    }

    func getDefaultCalendar() -> EKCalendar? {
        return eventStore.defaultCalendarForNewEvents
    }

    func getAvailableCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event)
    }
}
