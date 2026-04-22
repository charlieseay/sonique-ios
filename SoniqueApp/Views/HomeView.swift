import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: SoniqueSettings
    @EnvironmentObject private var session: SessionManager
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.soniqueBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.top, 4)
                    .padding(.horizontal, 24)

                Spacer()

                // Central orb
                OrbView(
                    sessionState: session.sessionState,
                    agentState: session.agentState
                )

                Spacer().frame(height: 32)

                // State label
                stateLabel

                Spacer()

                // Action area
                actionArea
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(session)
        }
        .onAppear {
            session.startHealthChecks(settings: settings)
        }
        .onDisappear {
            session.stopHealthChecks()
        }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack {
            // App wordmark
            Text("sonique")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.soniqueAccent, .soniqueAccent2],
                                   startPoint: .leading, endPoint: .trailing)
                )

            Spacer()

            // Server status badge
            serverStatusBadge

            // Settings
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.soniqueSubtext)
            }
            .padding(.leading, 8)
        }
    }

    private var serverStatusBadge: some View {
        let status: StatusBadge.Status
        if session.sessionState.isActive {
            status = .active
        } else {
            switch session.serverHealth.status {
            case .online:   status = .online
            case .offline:  status = .offline
            case .checking: status = .checking
            }
        }
        return StatusBadge(status: status)
    }

    private var stateLabel: some View {
        VStack(spacing: 6) {
            Text(primaryLabel)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.soniqueText)
                .animation(.easeInOut(duration: 0.3), value: primaryLabel)

            if let sub = subLabel {
                Text(sub)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.soniqueSubtext)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 32)
    }

    private var primaryLabel: String {
        switch session.sessionState {
        case .idle:
            return settings.isConfigured ? "Ready" : "Not configured"
        case .connecting:
            return "Connecting…"
        case .active:
            return session.agentState.label
        case .disconnecting:
            return "Ending…"
        case .error(let msg):
            return msg
        }
    }

    private var subLabel: String? {
        switch session.sessionState {
        case .idle where !settings.isConfigured:
            return "Tap the gear to set your server URL"
        case .idle:
            return settings.normalizedServerURL
        case .active:
            return nil
        case .error:
            return "Tap to try again"
        default:
            return nil
        }
    }

    private var actionArea: some View {
        Group {
            switch session.sessionState {
            case .idle:
                connectButton

            case .connecting:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.soniqueAccent2)
                    .scaleEffect(1.2)

            case .active:
                disconnectButton

            case .disconnecting:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.soniqueSubtext)

            case .error:
                connectButton
            }
        }
        .frame(height: 60)
    }

    private var connectButton: some View {
        Button {
            Task { await session.connect(settings: settings) }
        } label: {
            Label("Start Session", systemImage: "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    settings.isConfigured
                        ? AnyShapeStyle(LinearGradient.soniqueAccent)
                        : AnyShapeStyle(Color.soniqueSurface),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
        .disabled(!settings.isConfigured)
        .animation(.easeInOut(duration: 0.2), value: settings.isConfigured)
    }

    private var disconnectButton: some View {
        Button {
            Task { await session.disconnect() }
        } label: {
            Label("End Session", systemImage: "stop.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.soniqueOffline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color.soniqueOffline.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.soniqueOffline.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(SoniqueSettings())
        .environmentObject(SessionManager())
}
