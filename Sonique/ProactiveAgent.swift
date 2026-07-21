import Foundation
import EventKit
import UserNotifications

/// Feature #4: Proactive Agent Mode
/// Time-based triggers with user opt-in for calendar, weather, tasks
class ProactiveAgent: ObservableObject {
    static let shared = ProactiveAgent()

    @Published var calendarEnabled = false
    @Published var weatherEnabled = false
    @Published var tasksEnabled = false

    private let eventStore = EKEventStore()
    private var timer: Timer?

    private init() {
        // Load saved preferences
        calendarEnabled = UserDefaults.standard.bool(forKey: "proactive_calendar")
        weatherEnabled = UserDefaults.standard.bool(forKey: "proactive_weather")
        tasksEnabled = UserDefaults.standard.bool(forKey: "proactive_tasks")
    }

    // MARK: - Permissions

    func requestCalendarAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            print("[ProactiveAgent] Calendar access denied: \(error)")
            return false
        }
    }

    func requestNotificationAccess() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("[ProactiveAgent] Notification access denied: \(error)")
            return false
        }
    }

    // MARK: - Enable/Disable Categories

    func enableCalendar() async {
        guard await requestCalendarAccess() else { return }
        calendarEnabled = true
        UserDefaults.standard.set(true, forKey: "proactive_calendar")
        startProactiveMode()
    }

    func disableCalendar() {
        calendarEnabled = false
        UserDefaults.standard.set(false, forKey: "proactive_calendar")
        checkStopTimer()
    }

    func enableWeather() {
        weatherEnabled = true
        UserDefaults.standard.set(true, forKey: "proactive_weather")
        startProactiveMode()
    }

    func disableWeather() {
        weatherEnabled = false
        UserDefaults.standard.set(false, forKey: "proactive_weather")
        checkStopTimer()
    }

    func enableTasks() {
        tasksEnabled = true
        UserDefaults.standard.set(true, forKey: "proactive_tasks")
        startProactiveMode()
    }

    func disableTasks() {
        tasksEnabled = false
        UserDefaults.standard.set(false, forKey: "proactive_tasks")
        checkStopTimer()
    }

    // MARK: - Proactive Checks

    private func startProactiveMode() {
        guard timer == nil else { return }

        // Check every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { await self?.checkProactiveUpdates() }
        }

        // Immediate first check
        Task { await checkProactiveUpdates() }
    }

    private func checkStopTimer() {
        if !calendarEnabled && !weatherEnabled && !tasksEnabled {
            timer?.invalidate()
            timer = nil
        }
    }

    private func checkProactiveUpdates() async {
        var updates: [String] = []

        // Calendar check
        if calendarEnabled {
            if let upcomingEvent = await getNextEvent() {
                updates.append("📅 \(upcomingEvent)")
            }
        }

        // Weather check
        if weatherEnabled {
            // TODO: Implement weather check
            // For now, placeholder
        }

        // Tasks check
        if tasksEnabled {
            // TODO: Implement tasks check
            // For now, placeholder
        }

        // Send notification if there are updates
        if !updates.isEmpty {
            await sendProactiveNotification(updates.joined(separator: "\n"))
        }
    }

    private func getNextEvent() async -> String? {
        let calendar = Calendar.current
        let now = Date()
        let oneHourFromNow = calendar.date(byAdding: .hour, value: 1, to: now)!

        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: oneHourFromNow,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate)

        if let nextEvent = events.first {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: nextEvent.startDate)
            return "\(nextEvent.title ?? "Event") at \(timeStr)"
        }

        return nil
    }

    private func sendProactiveNotification(_ message: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Quinn"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Immediate
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[ProactiveAgent] Failed to send notification: \(error)")
        }
    }
}
