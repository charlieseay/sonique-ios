import SwiftUI

@main
struct SoniqueApp: App {
    @StateObject private var bonjourDiscovery = BonjourDiscovery()

    init() {
        // Start publishing device context to iCloud
        DeviceContextPublisher.shared.startPublishing()

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Auto-discover SoniqueBar backend on launch
                    bonjourDiscovery.start()
                }
                .environmentObject(bonjourDiscovery)
        }
    }
}
