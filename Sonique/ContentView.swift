import SwiftUI

struct ContentView: View {
    @StateObject private var voiceLoop = VoiceLoop()
    @State private var isHealthy = false
    @State private var showDebug = false

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.08, green: 0.08, blue: 0.14)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text(appVersion)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.leading)

                    Spacer()

                    Button(action: { showDebug.toggle() }) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing)
                }
                .padding(.top, 16)

                Spacer()

                // Model load progress (only shown once on first launch)
                if let stt = voiceLoop.speechRecognition, !stt.isModelLoaded {
                    VStack(spacing: 10) {
                        Text("Loading voice model...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        ProgressView(value: stt.modelLoadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                            .tint(.purple)
                    }
                    .padding(.bottom, 40)
                }

                // Response text (shows while speaking)
                if !voiceLoop.partialResponse.isEmpty {
                    Text(voiceLoop.partialResponse)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                } else if !voiceLoop.lastResponse.isEmpty && !voiceLoop.isProcessing {
                    Text(voiceLoop.lastResponse)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }

                // What the user said
                if !voiceLoop.lastTranscript.isEmpty {
                    Text(voiceLoop.lastTranscript)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }

                // Mic button
                Button(action: toggleVoice) {
                    ZStack {
                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 88, height: 88)
                            .shadow(color: micButtonColor.opacity(0.5), radius: 20)

                        if voiceLoop.isInitializing || voiceLoop.isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.2)
                        } else {
                            Image(systemName: voiceLoop.isActive ? "waveform" : "mic.fill")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(voiceLoop.isInitializing)

                // Status label
                Text(statusText)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 16)

                Spacer()

                // Debug log (hidden by default)
                if showDebug {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(voiceLoop.debugLog.suffix(30).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.8))
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    .background(Color.black.opacity(0.5))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: voiceLoop.isActive)
        .animation(.easeInOut(duration: 0.2), value: voiceLoop.partialResponse)
        .task {
            isHealthy = await voiceLoop.checkConnection()
        }
        .alert("Error", isPresented: .constant(voiceLoop.error != nil && !voiceLoop.isInitializing)) {
            Button("OK") { voiceLoop.error = nil }
        } message: {
            Text(voiceLoop.error ?? "")
        }
    }

    // MARK: - Actions

    private func toggleVoice() {
        if voiceLoop.isActive {
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

    private var micButtonColor: Color {
        if voiceLoop.isProcessing { return .purple }
        if voiceLoop.isActive { return Color(red: 0.9, green: 0.2, blue: 0.2) }
        return Color(red: 0.3, green: 0.3, blue: 0.9)
    }

    private var statusText: String {
        if !isHealthy { return "SoniqueBar unreachable" }
        if voiceLoop.isInitializing { return "Loading..." }
        if voiceLoop.isProcessing { return "Thinking..." }
        if voiceLoop.isActive { return "Listening" }
        return "Tap to speak"
    }
}

#Preview {
    ContentView()
}
