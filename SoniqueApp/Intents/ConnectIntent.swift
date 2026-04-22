import AppIntents
import Foundation

/// Siri App Intent — triggered by "Hey Siri, Ask Sonique" (or custom phrase).
/// Default phrases work immediately without user setup.
struct ConnectToSoniqueIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Sonique session"
    static var description = IntentDescription(
        "Open Sonique and immediately start a voice session with your AI assistant.",
        categoryName: "Voice"
    )
    // Bring the app to foreground so the user sees the UI
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .soniqueConnectIntent, object: nil)
        return .result()
    }
}

/// Pre-built app shortcuts — these phrases work immediately with Siri
/// without any user configuration required.
struct SoniqueAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectToSoniqueIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Start \(.applicationName)",
                "Open \(.applicationName) session",
            ],
            shortTitle: "Start session",
            systemImageName: "waveform"
        )
    }
}

extension Notification.Name {
    static let soniqueConnectIntent = Notification.Name("com.seayniclabs.sonique.connectIntent")
}
