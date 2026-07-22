import SwiftUI

@main
struct SoniqueApp: App {
    @StateObject private var bonjourDiscovery = BonjourDiscovery()

    init() {
        // Start publishing device context to iCloud
        DeviceContextPublisher.shared.startPublishing()

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Auto-configure from iCloud-synced preferences (Phase 1 auto-discovery)
        Task {
            await Self.autoConfigureFromiCloud()
        }
    }

    @MainActor
    private static func autoConfigureFromiCloud() {
        // Load preferences from iCloud (synced by SoniqueBar on Mac)
        let prefs = SoniqueBrain.shared.loadPreferences()

        // Only auto-configure if user hasn't manually set values
        let hasManualURL = !(UserDefaults.standard.string(forKey: "serverURL") ?? "").isEmpty
        let hasManualToken = !(UserDefaults.standard.string(forKey: "authToken") ?? "").isEmpty

        if !hasManualURL, let serverURL = prefs.serverURL {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            NSLog("[AutoConfig] Set serverURL from iCloud: \(serverURL)")
        }

        if !hasManualToken, let authToken = prefs.authToken {
            UserDefaults.standard.set(authToken, forKey: "authToken")
            NSLog("[AutoConfig] Set authToken from iCloud: <redacted>")
        }
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
