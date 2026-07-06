import AppIntents
import SwiftUI

/// App Intent that Siri / the Shortcuts app can run. The user builds a Shortcut
/// ("Hey Siri, Cael" → run this), which launches Sonique and auto-starts listening.
/// Siri is the always-on wake detector, so Sonique never has to monitor the mic in
/// the background just to catch a wake word — battery-friendly.
@available(iOS 16.0, *)
struct StartListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Listening"
    static var description = IntentDescription("Opens your assistant and starts listening.")

    // Bring the app to the foreground when run.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Signal the app to auto-start the mic as soon as it's active.
        AppLaunchState.shared.shouldAutoStartListening = true
        return .result()
    }
}

/// Shared launch state read by ContentView on appear/foreground.
@MainActor
final class AppLaunchState: ObservableObject {
    static let shared = AppLaunchState()
    @Published var shouldAutoStartListening = false
    private init() {}
}

@available(iOS 16.0, *)
struct SoniqueShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Talk to \(.applicationName)",
                "Hey \(.applicationName)"
            ],
            shortTitle: "Start Listening",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: SlackPostIntent(),
            phrases: [
                "Post to Slack with \(.applicationName)",
                "Slack message with \(.applicationName)",
                "Send Slack with \(.applicationName)"
            ],
            shortTitle: "Post to Slack",
            systemImageName: "number"
        )
        AppShortcut(
            intent: LinearCreateIntent(),
            phrases: [
                "Create Linear task with \(.applicationName)",
                "Linear task with \(.applicationName)",
                "New Linear issue with \(.applicationName)"
            ],
            shortTitle: "Create Linear Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: GitHubSearchIntent(),
            phrases: [
                "Search GitHub with \(.applicationName)",
                "GitHub search with \(.applicationName)",
                "Find GitHub pull requests with \(.applicationName)"
            ],
            shortTitle: "Search GitHub",
            systemImageName: "chevron.left.forwardslash.chevron.right"
        )
        AppShortcut(
            intent: GitHubCreateIssueIntent(),
            phrases: [
                "Create GitHub issue with \(.applicationName)",
                "GitHub issue with \(.applicationName)",
                "New GitHub issue with \(.applicationName)"
            ],
            shortTitle: "Create GitHub Issue",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: NotionCreateIntent(),
            phrases: [
                "Create Notion page with \(.applicationName)",
                "Notion page with \(.applicationName)",
                "New Notion entry with \(.applicationName)"
            ],
            shortTitle: "Create Notion Page",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: DockerListIntent(),
            phrases: [
                "List Docker with \(.applicationName)",
                "Docker containers with \(.applicationName)",
                "Show Docker with \(.applicationName)"
            ],
            shortTitle: "List Docker",
            systemImageName: "shippingbox"
        )
    }
}
