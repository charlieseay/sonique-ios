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

/// Siri App Intent — provides current network quality status.
struct CheckNetworkStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check network status"
    static var description = IntentDescription(
        "Get Sonique's current network connection summary.",
        categoryName: "Voice"
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let status = NetworkMonitor.shared.qualityAssessment()
        return .result(dialog: IntentDialog(stringLiteral: status.summary))
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
        AppShortcut(
            intent: CheckNetworkStatusIntent(),
            phrases: [
                "What's my connection in \(.applicationName)",
                "Check my connection in \(.applicationName)",
                "How is my network in \(.applicationName)",
            ],
            shortTitle: "Check network",
            systemImageName: "network"
        )
    }
}

extension Notification.Name {
    static let soniqueConnectIntent = Notification.Name("com.seayniclabs.sonique.connectIntent")
}
