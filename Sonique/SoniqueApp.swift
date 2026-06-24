import SwiftUI

@main
struct SoniqueApp: App {
    init() {
        // Start publishing device context to iCloud
        DeviceContextPublisher.shared.startPublishing()

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
