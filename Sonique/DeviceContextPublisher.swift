import Foundation
import UIKit

/// Publishes device context to iCloud for SoniqueBar
class DeviceContextPublisher {
    static let shared = DeviceContextPublisher()

    private let iCloudDir = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.seayniclabs.sonique")?
        .appendingPathComponent("Documents/SoniqueProfiles/Desktop")

    private var updateTimer: Timer?

    private init() {
        // Create directory if needed
        if let dir = iCloudDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Start publishing context
        startPublishing()
    }

    func startPublishing() {
        // Publish immediately
        publishContext()

        // Then publish every 30 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.publishContext()
        }
    }

    func stopPublishing() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func publishContext() {
        guard let contextFile = iCloudDir?.appendingPathComponent("device_context.json") else {
            return
        }

        // Gather context
        let timezone = TimeZone.current.identifier
        let batteryLevel = UIDevice.current.batteryLevel
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Location would come from CoreLocation - for now use timezone-based guess
        let location = getLocationFromTimezone(timezone)

        let context = DeviceContextData(
            timezoneIdentifier: timezone,
            location: location,
            batteryLevel: batteryLevel >= 0 ? batteryLevel : nil,
            isLowPowerMode: isLowPowerMode,
            timestamp: Date()
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(context)
            try data.write(to: contextFile, options: .atomic)

            print("[DeviceContextPublisher] Published: \(timezone), battery: \(batteryLevel * 100)%")
        } catch {
            print("[DeviceContextPublisher] Failed to publish: \(error)")
        }
    }

    private func getLocationFromTimezone(_ identifier: String) -> String? {
        // Simple timezone -> location mapping
        let mapping: [String: String] = [
            "America/Chicago": "Central Time",
            "America/New_York": "Eastern Time",
            "America/Los_Angeles": "Pacific Time",
            "America/Denver": "Mountain Time",
            "America/Phoenix": "Arizona",
            "Pacific/Honolulu": "Hawaii",
            "America/Anchorage": "Alaska"
        ]

        return mapping[identifier]
    }
}

struct DeviceContextData: Codable {
    let timezoneIdentifier: String?
    let location: String?
    let batteryLevel: Float?
    let isLowPowerMode: Bool?
    let timestamp: Date
}
