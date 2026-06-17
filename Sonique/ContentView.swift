import SwiftUI

struct ContentView: View {
    @StateObject private var voiceLoop = VoiceLoop()
    @ObservedObject private var profile = AssistantProfile.shared
    @ObservedObject private var launchState = AppLaunchState.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHealthy = false
    @State private var showDebug = false
    @State private var showVoicePicker = false
    @State private var showAssistantSettings = false
    @State private var showReportSheet = false
    @State private var selectedVoiceID = Config.selectedVoiceID
    @State private var apiKey = ""

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.08, green: 0.08, blue: 0.14)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack(spacing: 8) {
                    // Assistant identity — tap to rename / set photo
                    Button(action: { showAssistantSettings = true }) {
                        HStack(spacing: 7) {
                            if let img = profile.photo {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 28, height: 28).clipShape(Circle())
                            } else {
                                Circle().fill(Color.purple.opacity(0.4))
                                    .frame(width: 28, height: 28)
                                    .overlay(Image(systemName: "waveform").font(.system(size: 13)).foregroundColor(.white))
                            }
                            Text(profile.name)
                                .font(.callout.weight(.medium))   // Dynamic Type
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(minHeight: 44)                     // HIG 44pt tap target
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading)
                    .accessibilityLabel("Assistant settings")
                    .accessibilityHint("Rename your assistant or set a photo")

                    Spacer()

                    // Voice picker
                    Button(action: { showVoicePicker = true }) {
                        Image(systemName: "waveform.circle")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 44, height: 44)         // HIG 44pt
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose voice")

                    Button(action: { showDebug.toggle() }) {
                        Image(systemName: "ladybug")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.35))
                            .frame(width: 44, height: 44)         // HIG 44pt
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing)
                    .accessibilityLabel("Toggle debug log")
                }
                .padding(.top, 8)

                // Connection banner — friendly, explains why, offers help. Never an alert.
                if !voiceLoop.connectionOK && !voiceLoop.connectionMessage.isEmpty {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.exclamationmark")
                                .foregroundColor(.orange)
                            Text(voiceLoop.connectionMessage)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 10) {
                            Button("Retry") {
                                Task { await voiceLoop.checkConnection() }
                            }
                            .font(.footnote.weight(.semibold))
                            Button("Connection settings") { showAssistantSettings = true }
                                .font(.footnote)
                            Button("Report a problem") { showReportSheet = true }
                                .font(.footnote)
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                Spacer()

                // Mic button with animated state indicator
                Button(action: toggleVoice) {
                    ZStack {
                        // Animated state rings
                        if voiceLoop.isTokenSeeding {
                            // Token seeding: fast shimmering green rings
                            TokenSeedingRings()
                                .id("tokenSeeding")
                        } else if voiceLoop.isProcessing {
                            // Thinking: pulsing purple rings
                            PulsingRings(color: .purple, count: 3)
                                .id("processing")
                        } else if voiceLoop.isActive {
                            // Listening: pulsing blue rings
                            PulsingRings(color: .blue, count: 2)
                                .id("listening")
                        }

                        // Progress ring (only during model load)
                        if isLoadingModel {
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 5)
                                .frame(width: 108, height: 108)
                            Circle()
                                .trim(from: 0, to: loadProgress)
                                .stroke(
                                    Color.purple,
                                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                                )
                                .frame(width: 108, height: 108)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: loadProgress)
                        }

                        // Main button
                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 88, height: 88)
                            .shadow(color: micButtonColor.opacity(0.5), radius: 20)

                        // Icon
                        if isLoadingModel {
                            Text("\(Int(loadProgress * 100))%")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: voiceLoop.isActive ? "waveform" : "mic.fill")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingModel)
                .accessibilityLabel(voiceLoop.isActive ? "Stop listening" : "Start listening")
                .accessibilityHint(voiceLoop.isActive ? "Double tap to stop" : "Double tap to talk to \(profile.name)")
                .accessibilityAddTraits(.isButton)

                // Status + detail lines
                VStack(spacing: 4) {
                    Text(primaryStatus)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.7))
                    if !secondaryStatus.isEmpty {
                        Text(secondaryStatus)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 32)

                Spacer()

                // Version number
                Text(appVersion)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.bottom, 8)

                // Debug panel (hidden by default)
                if showDebug {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(sttDebugLines.suffix(30).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.8))
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .background(Color.black.opacity(0.5))
                }
            }

            // Ephemeral image artifact (Snapchat-style) — stays until X tapped or the
            // conversation organically advances (VoiceLoop clears it on the next turn).
            if let url = voiceLoop.artifactURL {
                ArtifactOverlay(url: url) { voiceLoop.artifactURL = nil }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: voiceLoop.artifactURL)
        .animation(.easeInOut(duration: 0.2), value: voiceLoop.isActive)
        .animation(.easeInOut(duration: 0.2), value: voiceLoop.isProcessing)
        .animation(.easeInOut(duration: 0.2), value: voiceLoop.partialResponse)
        .task {
            isHealthy = await voiceLoop.checkConnection()
            apiKey = (try? await Config.getAPIKey()) ?? ""
            await maybeAutoStart()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await maybeAutoStart() }
            }
        }
        .onChange(of: launchState.shouldAutoStartListening) { _, want in
            if want { Task { await maybeAutoStart() } }
        }
        .sheet(isPresented: $showVoicePicker) {
            VoiceSelector(apiKey: apiKey, selectedVoiceID: $selectedVoiceID)
        }
        .sheet(isPresented: $showAssistantSettings) {
            AssistantSettingsView()
        }
        .sheet(isPresented: $showReportSheet) {
            DiagnosticsReportView(connectionOK: voiceLoop.connectionOK,
                                  activeEndpoint: HTTPClient.activeBaseURL)
        }
        .alert("Error", isPresented: .constant(voiceLoop.error != nil && !voiceLoop.isInitializing)) {
            Button("OK") { voiceLoop.error = nil }
        } message: {
            Text(voiceLoop.error ?? "")
        }
    }

    // MARK: - Actions

    /// Auto-start listening when launched via the Siri Shortcut (StartListeningIntent).
    private func maybeAutoStart() async {
        guard launchState.shouldAutoStartListening, !voiceLoop.isActive else { return }
        launchState.shouldAutoStartListening = false
        await voiceLoop.start()
    }

    private func toggleVoice() {
        // Haptic confirmation for the primary action (HIG).
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if voiceLoop.isProcessing {
            // Interrupt long response - stop speaking and resume listening
            voiceLoop.stopSpeaking()
        } else if voiceLoop.isActive {
            // Stop the whole session
            voiceLoop.stop()
        } else {
            Task { await voiceLoop.start() }
        }
    }

    // MARK: - UI State

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    // VoiceLoop's pipeline log (Apple STT has no separate trace array)
    private var sttDebugLines: [String] {
        voiceLoop.debugLog
    }

    private var micButtonColor: Color {
        if isLoadingModel { return .purple.opacity(0.7) }
        if voiceLoop.isProcessing { return .purple }
        if voiceLoop.isActive { return Color(red: 0.9, green: 0.2, blue: 0.2) }
        return Color(red: 0.3, green: 0.3, blue: 0.9)
    }

    // Apple STT initializes near-instantly — only "loading" during permission/TTS setup.
    private var isLoadingModel: Bool {
        voiceLoop.isInitializing
    }

    private var loadProgress: Double { voiceLoop.isInitializing ? 0.5 : 0 }

    private var primaryStatus: String {
        if !isHealthy && !isLoadingModel { return "SoniqueBar unreachable" }
        if isLoadingModel { return "Starting…" }
        if voiceLoop.isTokenSeeding { return "Responding…" }
        if voiceLoop.isProcessing { return "Thinking…" }
        if voiceLoop.isActive { return "Listening" }
        return "Tap to speak"
    }

    private var secondaryStatus: String {
        if isLoadingModel { return "Setting up microphone" }
        if !isHealthy { return "Check that SoniqueBar is running on the Mac" }
        if voiceLoop.isActive { return "Speak naturally — pause when you're done" }
        return ""
    }
}

/// Animated pulsing rings around the mic button to show state
struct PulsingRings: View {
    let color: Color
    let count: Int
    @State private var animationValues: [CGFloat]

    init(color: Color, count: Int) {
        self.color = color
        self.count = count
        _animationValues = State(initialValue: Array(repeating: 0, count: count))
    }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .frame(width: 88 + CGFloat(index * 30), height: 88 + CGFloat(index * 30))
                    .scaleEffect(animationValues[index])
                    .opacity(1.0 - animationValues[index])
            }
        }
        .onAppear {
            for index in 0..<count {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                    .delay(Double(index) * 0.3)
                ) {
                    animationValues[index] = 1
                }
            }
        }
    }
}

/// Fast shimmering rings that indicate tokens streaming in (like particle seeding)
struct TokenSeedingRings: View {
    @State private var animationValues: [CGFloat]
    let count = 4

    init() {
        _animationValues = State(initialValue: Array(repeating: 0, count: 4))
    }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.green.opacity(0.6), .cyan.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 88 + CGFloat(index * 20), height: 88 + CGFloat(index * 20))
                    .scaleEffect(animationValues[index])
                    .opacity(0.8 - (animationValues[index] * 0.8))
            }
        }
        .onAppear {
            for index in 0..<count {
                withAnimation(
                    .easeOut(duration: 0.4)
                    .repeatForever(autoreverses: false)
                    .delay(Double(index) * 0.1)
                ) {
                    animationValues[index] = 1
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
