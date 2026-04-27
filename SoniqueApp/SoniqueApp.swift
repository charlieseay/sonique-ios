import SwiftUI
import AppIntents
import AVFoundation
import GoogleMobileAds

@main
struct SoniqueApp: App {
    @StateObject private var settings = SoniqueSettings()
    @StateObject private var session = SessionManager()
    @StateObject private var premium = PremiumManager()
    @StateObject private var network = NetworkMonitor.shared

    init() {
        MobileAds.shared.start()
        configureAudioSession()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Configure for voice chat with continuous playback
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .defaultToSpeaker,
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                    .duckOthers  // Lower other audio, don't silence
                ]
            )
            // Ensure the session is active before any audio operations
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error configuring audio session: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(session)
                .environmentObject(premium)
                .environmentObject(network)
                .preferredColorScheme(.dark)
                // URL scheme: sonique://connect?local=...&external=...&key=... (new)
                //             sonique://connect?url=...&key=...                  (legacy)
                //             sonique://voice                                    (Siri shortcut)
                .onOpenURL { url in
                    guard url.scheme == "sonique" else { return }
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       url.host == "connect" {
                        let params = components.queryItems ?? []
                        if let local = params.first(where: { $0.name == "local" })?.value {
                            settings.serverURL = local
                        } else if let legacy = params.first(where: { $0.name == "url" })?.value {
                            settings.serverURL = legacy
                        }
                        if let ext = params.first(where: { $0.name == "external" })?.value {
                            settings.externalURL = ext
                        }
                        if let key = params.first(where: { $0.name == "key" })?.value {
                            settings.apiKey = key
                        }
                        settings.hasCompletedSetup = !settings.serverURL.isEmpty
                    } else {
                        triggerConnect()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .soniqueConnectIntent)) { _ in
                    triggerConnect()
                }
        }
    }

    private func triggerConnect() {
        guard settings.isConfigured else { return }
        Task { @MainActor in
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
