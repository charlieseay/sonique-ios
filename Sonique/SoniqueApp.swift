import SwiftUI

@main
struct SoniqueApp: App {
    init() {
        // Initialize native capabilities on launch
        Task { @MainActor in
            NativeCapabilities.shared.setupHomeKit()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
