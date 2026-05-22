import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var settings: SoniqueSettings
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var premium: PremiumManager
    @EnvironmentObject private var wakeWord: WakeWordDetector
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

                if settings.isConfigured {
                    VStack(spacing: 4) {
                        Text(settings.llmRoutingSummaryLine)
                            .font(.caption2)
                            .foregroundStyle(Color.soniqueSubtext.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(settings.fallbackPolicy.routingHint)
                            .font(.caption2)
                            .foregroundStyle(Color.soniqueSubtext.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                        if settings.nvidiaFeatureEnabled {
                            Text("NVIDIA NIM: experimental UI only until CAAL is wired.")
                                .font(.caption2)
                                .foregroundStyle(Color.soniqueSubtext.opacity(0.65))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 24)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("LLM routing preferences")
                }

                Spacer()

                // Action area
                actionArea
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                // Ad banner — hidden for premium users
                AdBannerView()
                    .environmentObject(premium)
                    .padding(.bottom, premium.isPremium ? 0 : 16)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(session)
        }
        .onAppear {
            session.startHealthChecks(settings: settings)
            wakeWord.onDetected = { [weak wakeWord = wakeWord, weak session = session] in
                guard let session else { return }
                wakeWord?.stop()
                Task { await session.connect(settings: settings) }
            }
            if settings.wakeWordEnabled, settings.isConfigured, session.sessionState == .idle {
                wakeWord.start()
            }
        }
        .onDisappear {
            session.stopHealthChecks()
            wakeWord.stop()
        }
        .onChange(of: session.sessionState) { _, newState in
            if case .idle = newState, settings.wakeWordEnabled, settings.isConfigured {
                wakeWord.start()
            } else if case .idle = newState {
                // not enabled — ensure stopped
            } else {
                wakeWord.stop()
            }
        }
        .onChange(of: settings.wakeWordEnabled) { _, enabled in
            if enabled, settings.isConfigured, session.sessionState == .idle {
                wakeWord.start()
            } else {
                wakeWord.stop()
            }
        }
        .overlay {
            if let image = session.screenCaptureImage {
                ScreenCaptureOverlay(
                    image: image,
                    description: session.screenCaptureDescription
                ) {
                    session.screenCaptureImage = nil
                    session.screenCaptureDescription = ""
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .animation(.easeInOut(duration: 0.22), value: session.screenCaptureImage != nil)
            }
        }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack(spacing: 10) {
            // Avatar + name
            HStack(spacing: 8) {
                avatarBadge
                Text(session.profile?.name ?? "sonique")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.soniqueAccent, .soniqueAccent2],
                                       startPoint: .leading, endPoint: .trailing)
                    )
            }

            Spacer()

            serverStatusBadge

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.soniqueSubtext)
            }
            .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private var avatarBadge: some View {
        if let data = session.avatarData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(LinearGradient(colors: [.soniqueAccent, .soniqueAccent2],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundStyle(.white))
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

// MARK: - Screen Capture Overlay

struct ScreenCaptureOverlay: View {
    let image: UIImage
    let description: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                // Header bar
                HStack {
                    if !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                // Image — pinch-to-zoom via ScrollView
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(10)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                }

                // Dismiss hint
                Text("Tap anywhere or say \"close\" to dismiss")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 20)
            }
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(SoniqueSettings())
        .environmentObject(SessionManager())
}
