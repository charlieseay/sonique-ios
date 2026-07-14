import Foundation
import EventKit

/// Native iOS capabilities — Calendar and Reminders via EventKit.
/// App targets iOS 17.0+, so all EventKit full-access APIs are always available.
@MainActor
class NativeCapabilities: NSObject {
    static let shared = NativeCapabilities()
    private let eventStore = EKEventStore()

    // MARK: - Calendar

    func requestCalendarAccess() async -> Bool {
        do { return try await eventStore.requestFullAccessToEvents() } catch { return false }
    }

    func getTodayEvents() async -> [String] {
        guard await requestCalendarAccess() else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        return eventStore.events(matching: predicate).map {
            "\($0.title ?? "Untitled") at \(fmt.string(from: $0.startDate))"
        }
    }

    func createCalendarEvent(title: String, date: Date, duration: Int = 60) async -> Bool {
        guard await requestCalendarAccess() else { return false }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(TimeInterval(duration * 60))
        event.calendar = eventStore.defaultCalendarForNewEvents
        do { try eventStore.save(event, span: .thisEvent); return true } catch { return false }
    }

    // MARK: - Reminders

    func requestRemindersAccess() async -> Bool {
        do { return try await eventStore.requestFullAccessToReminders() } catch { return false }
    }

    func getReminders() async -> [String] {
        guard await requestRemindersAccess() else { return [] }
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: eventStore.predicateForReminders(in: nil)) { reminders in
                continuation.resume(returning: reminders?.filter { !$0.isCompleted }.map { $0.title ?? "Untitled" } ?? [])
            }
        }
    }

    func createReminder(title: String, dueDate: Date? = nil) async -> Bool {
        guard await requestRemindersAccess() else { return false }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        do { try eventStore.save(reminder, commit: true); return true } catch { return false }
    }
}
