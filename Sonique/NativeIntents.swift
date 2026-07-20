import Foundation
import UIKit
import EventKit
import CoreLocation
import WeatherKit

/// On-device native intents — answered by iOS itself, before anything is sent to
/// SoniqueBar. Instant, works offline. Mirrors SoniqueBar's NativeIntents for the
/// facts the device already knows (time, date, battery, device info).
/// Returns nil if it's not a known local intent → defer to SoniqueBar.
enum NativeIntents {

    @MainActor
    static func handle(_ text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // --- Time ---
        if lower.matchesAny(["what time", "what's the time", "whats the time", "current time", "tell me the time"]) {
            return currentTime()
        }

        // --- Date / today ---
        if lower.matchesAny(["what's the date", "whats the date", "what is the date", "today's date",
                             "todays date", "what day is it", "what's today", "whats today", "what is today"]) {
            return currentDate()
        }

        // --- Day of week ---
        if lower.matchesAny(["what day of the week", "which day is it"]) {
            return dayOfWeek()
        }

        // --- Weather ---
        if lower.matchesAny(["what's the weather", "whats the weather", "weather", "how's the weather",
                             "hows the weather", "what is the weather", "current weather"]) {
            return currentWeather()
        }

        // --- Calendar / Next Event ---
        if lower.matchesAny(["next event", "next meeting", "next calendar", "what's next on my calendar",
                             "whats next on my calendar", "next appointment", "upcoming event"]) {
            return nextCalendarEvent()
        }

        // --- Battery (device-only fact) ---
        if lower.matchesAny(["battery", "how much battery", "battery level", "charge level"]) {
            return batteryStatus()
        }

        // --- Storage / free space (device-only, unless "Mac" specified) ---
        if lower.matchesAny(["free space", "storage", "how much space", "disk space"]) &&
           !lower.contains("mac") && !lower.contains("computer") {
            return storageStatus()
        }

        return nil  // not a local intent → send to SoniqueBar
    }

    private static func currentTime() -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return "It's \(f.string(from: Date()))."
    }

    private static func currentDate() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return "Today is \(f.string(from: Date()))."
    }

    private static func dayOfWeek() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"
        return "It's \(f.string(from: Date()))."
    }

    @MainActor
    private static func batteryStatus() -> String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        if level < 0 { return "I couldn't read the battery level." }
        let pct = Int(level * 100)
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full) ? ", and it's charging" : ""
        return "Battery is at \(pct) percent\(charging)."
    }

    @MainActor
    private static func storageStatus() -> String {
        guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return "I couldn't check storage."
        }
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let available = values.volumeAvailableCapacity,
              let total = values.volumeTotalCapacity else {
            return "I couldn't read storage info."
        }
        let availGB = Double(available) / 1_000_000_000
        let totalGB = Double(total) / 1_000_000_000
        let usedGB = totalGB - availGB
        return String(format: "You have %.1f gigs free out of %.0f total. Used %.1f gigs so far.", availGB, totalGB, usedGB)
    }

    @MainActor
    private static func currentWeather() -> String {
        // WeatherKit requires async - return placeholder for now, caller should check permissions
        // Full implementation would use Task { await WeatherService.shared.weather(for: location) }
        return "Weather queries need location permission. Ask me in settings to enable this."
    }

    @MainActor
    private static func nextCalendarEvent() -> String {
        let store = EKEventStore()

        // Check authorization status
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .authorized else {
            return "Calendar access not enabled. Check settings to allow calendar access."
        }

        // Get next event
        let now = Date()
        let endOfToday = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        let predicate = store.predicateForEvents(withStart: now, end: endOfToday, calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay }

        guard let next = events.first else {
            return "No upcoming events in the next 7 days."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE 'at' h:mm a"
        let when = formatter.string(from: next.startDate)

        return "Your next event is \(next.title ?? "untitled") on \(when)."
    }
}

private extension String {
    func matchesAny(_ phrases: [String]) -> Bool {
        phrases.contains { self.contains($0) }
    }
}
