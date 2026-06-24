import Foundation
import EventKit
import MessageUI
import HomeKit

/// Native iOS capabilities - uses Apple frameworks directly
/// Messages, Mail, Calendar, Reminders, HomeKit
@MainActor
class NativeCapabilities: NSObject, ObservableObject {
    static let shared = NativeCapabilities()

    private let eventStore = EKEventStore()
    private var homeManager: HMHomeManager?

    // MARK: - Calendar & Reminders

    func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                print("[NativeCapabilities] Calendar access error: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func requestRemindersAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                print("[NativeCapabilities] Reminders access error: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Get today's calendar events
    func getTodayEvents() async -> [String] {
        guard await requestCalendarAccess() else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        return events.map { event in
            "\(event.title ?? "Untitled") at \(formatter.string(from: event.startDate))"
        }
    }

    /// Create a calendar event
    func createCalendarEvent(title: String, date: Date, duration: Int = 60) async -> Bool {
        guard await requestCalendarAccess() else { return false }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = date
        event.endDate = date.addingTimeInterval(TimeInterval(duration * 60))
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent)
            return true
        } catch {
            print("[NativeCapabilities] Failed to create event: \(error)")
            return false
        }
    }

    /// Get all reminders
    func getReminders() async -> [String] {
        guard await requestRemindersAccess() else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: nil)

            eventStore.fetchReminders(matching: predicate) { reminders in
                let titles = reminders?.filter { !$0.isCompleted }.map { $0.title ?? "Untitled" } ?? []
                continuation.resume(returning: titles)
            }
        }
    }

    /// Create a reminder
    func createReminder(title: String, dueDate: Date? = nil) async -> Bool {
        guard await requestRemindersAccess() else { return false }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dueDate = dueDate {
            let dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = dueDateComponents
        }

        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            print("[NativeCapabilities] Failed to create reminder: \(error)")
            return false
        }
    }

    // MARK: - Messages

    /// Can send messages on this device?
    var canSendMessages: Bool {
        MFMessageComposeViewController.canSendText()
    }

    /// Get message composer (present this as a sheet)
    func getMessageComposer(to recipient: String, body: String) -> MFMessageComposeViewController? {
        guard MFMessageComposeViewController.canSendText() else { return nil }

        let composer = MFMessageComposeViewController()
        composer.recipients = [recipient]
        composer.body = body
        return composer
    }

    // MARK: - Mail

    /// Can send email on this device?
    var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }

    /// Get mail composer (present this as a sheet)
    func getMailComposer(to recipient: String, subject: String, body: String) -> MFMailComposeViewController? {
        guard MFMailComposeViewController.canSendMail() else { return nil }

        let composer = MFMailComposeViewController()
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        return composer
    }

    // MARK: - HomeKit

    func setupHomeKit() {
        homeManager = HMHomeManager()
    }

    /// Get HomeKit home
    var home: HMHome? {
        homeManager?.primaryHome
    }

    /// List all HomeKit lights
    func getLights() -> [HMAccessory] {
        guard let home = home else { return [] }

        return home.accessories.filter { accessory in
            accessory.services.contains { service in
                service.serviceType == HMServiceTypeLightbulb
            }
        }
    }

    /// Turn light on/off
    func setLight(name: String, on: Bool) async -> Bool {
        guard let home = home else { return false }

        guard let light = home.accessories.flatMap({ $0.services }).first(where: {
            $0.serviceType == HMServiceTypeLightbulb && $0.name == name
        }) else {
            return false
        }

        guard let powerChar = light.characteristics.first(where: {
            $0.characteristicType == HMCharacteristicTypePowerState
        }) else {
            return false
        }

        do {
            try await powerChar.writeValue(on)
            return true
        } catch {
            print("[NativeCapabilities] Failed to set light: \(error)")
            return false
        }
    }

    /// Activate HomeKit scene
    func activateScene(name: String) async -> Bool {
        guard let home = home else { return false }

        guard let scene = home.actionSets.first(where: { $0.name == name }) else {
            return false
        }

        do {
            try await home.executeActionSet(scene)
            return true
        } catch {
            print("[NativeCapabilities] Failed to activate scene: \(error)")
            return false
        }
    }

    /// List all scenes
    func getScenes() -> [String] {
        guard let home = home else { return [] }
        return home.actionSets.map { $0.name }
    }
}
