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

                // Response text (shows while speaking)
                if !voiceLoop.partialResponse.isEmpty {
                    Text(voiceLoop.partialResponse)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                } else if !voiceLoop.lastResponse.isEmpty && !voiceLoop.isProcessing && !isLoadingModel {
                    Text(voiceLoop.lastResponse)
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }

                // What the user said
                if !voiceLoop.lastTranscript.isEmpty && !isLoadingModel {
                    Text(voiceLoop.lastTranscript)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }

                // Mic button with progress ring around it
                Button(action: toggleVoice) {
                    ZStack {
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

                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 88, height: 88)
                            .shadow(color: micButtonColor.opacity(0.5), radius: 20)

                        if isLoadingModel {
                            Text("\(Int(loadProgress * 100))%")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        } else if voiceLoop.isProcessing {
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
                .disabled(isLoadingModel)

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

                // Debug panel (hidden by default)
                if showDebug {
                    VStack(spacing: 4) {
                        // Live mic level meter vs VAD threshold
                        if voiceLoop.isActive, let stt = voiceLoop.speechRecognition {
                            HStack(spacing: 6) {
                                Text("mic")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(Color.white.opacity(0.1))
                                        // level bar — scaled so 0.03 RMS ≈ full width
                                        Rectangle()
                                            .fill(stt.liveRMS > stt.vadSilenceThreshold ? Color.green : Color.gray)
                                            .frame(width: min(geo.size.width, geo.size.width * CGFloat(stt.liveRMS / 0.03)))
                                        // threshold marker
                                        Rectangle().fill(Color.red)
                                            .frame(width: 1)
                                            .offset(x: geo.size.width * CGFloat(stt.vadSilenceThreshold / 0.03))
                                    }
                                }
                                .frame(height: 10)
                                Text(String(format: "%.4f", stt.liveRMS))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.horizontal, 8)
                        }

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

    // Merge VoiceLoop's pipeline log with WhisperKit's VAD/transcript trace
    private var sttDebugLines: [String] {
        voiceLoop.debugLog + (voiceLoop.speechRecognition?.debugLines ?? [])
    }

    private var micButtonColor: Color {
        if isLoadingModel { return .purple.opacity(0.7) }
        if voiceLoop.isProcessing { return .purple }
        if voiceLoop.isActive { return Color(red: 0.9, green: 0.2, blue: 0.2) }
        return Color(red: 0.3, green: 0.3, blue: 0.9)
    }

    // Model is loading when STT exists but isn't loaded yet (or we're initializing it)
    private var isLoadingModel: Bool {
        if voiceLoop.isInitializing { return true }
        if let stt = voiceLoop.speechRecognition, !stt.isModelLoaded { return true }
        return false
    }

    private var loadProgress: Double {
        voiceLoop.speechRecognition?.modelLoadProgress ?? 0
    }

    // Primary line: WhisperKit's own status during load, else the voice-loop state
    private var primaryStatus: String {
        if !isHealthy && !isLoadingModel { return "SoniqueBar unreachable" }
        if isLoadingModel {
            let s = voiceLoop.speechRecognition?.loadStatus ?? ""
            return s.isEmpty ? "Preparing voice model" : s
        }
        if voiceLoop.isProcessing { return "Thinking…" }
        if voiceLoop.isActive { return "Listening" }
        return "Tap to speak"
    }

    // Secondary line: ETA / instructions during load
    private var secondaryStatus: String {
        if isLoadingModel {
            return voiceLoop.speechRecognition?.loadDetail ?? ""
        }
        if !isHealthy { return "Check that SoniqueBar is running on the Mac" }
        if voiceLoop.isActive { return "Speak naturally — pause when you're done" }
        return ""
    }
}

#Preview {
    ContentView()
}
