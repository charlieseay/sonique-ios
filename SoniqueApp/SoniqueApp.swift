import SwiftUI
import AppIntents

@main
struct SoniqueApp: App {
    @StateObject private var settings = SoniqueSettings()
    @StateObject private var session = SessionManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(session)
                .preferredColorScheme(.dark)
                // URL scheme: sonique://voice → auto-connect
                .onOpenURL { url in
                    guard url.scheme == "sonique" else { return }
                    triggerConnect()
                }
                // AppIntent notification (from Siri shortcut)
                .onReceive(NotificationCenter.default.publisher(for: .soniqueConnectIntent)) { _ in
                    triggerConnect()
                }
        }
    }

    private func triggerConnect() {
        guard settings.isConfigured else { return }
        Task { @MainActor in
            // Small delay so the window is fully presented
            try? await Task.sleep(for: .milliseconds(300))
            await session.connect(settings: settings, fromShortcut: true)
        }
    }
}

// MARK: - Root routing view

private struct RootView: View {
    @EnvironmentObject private var settings: SoniqueSettings

    var body: some View {
        if settings.hasCompletedSetup {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}
