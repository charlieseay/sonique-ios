import Foundation
import UIKit

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
}

private extension String {
    func matchesAny(_ phrases: [String]) -> Bool {
        phrases.contains { self.contains($0) }
    }
}
