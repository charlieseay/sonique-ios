import SwiftUI

struct ContentView: View {
    @StateObject private var voiceLoop = VoiceLoop()
    @State private var isHealthy = false
    @State private var showVoicePicker = false
    @State private var showSettings = false
    @State private var selectedVoice = Config.selectedVoice

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [.purple.opacity(0.3), .blue.opacity(0.3)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                // Error banner
                if let stt = voiceLoop.speechRecognition, !stt.lastError.isEmpty {
                    Text(stt.lastError)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                // Top bar with voice picker and settings
                HStack {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading)

                    Spacer()

                    Button(action: { showVoicePicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.wave.2.fill")
                                .font(.caption)
                            Text(selectedVoice.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing)
                }

                // Status
                VStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 40))
                        .foregroundColor(statusColor)

                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(.secondary)

                    // Debug info - ALWAYS show callback count
                    Text("Callbacks: \(voiceLoop.callbackCount) | Active: \(voiceLoop.isActive ? "YES" : "NO")")
                        .font(.caption)
                        .foregroundColor(.orange)

                    // Show transcript and errors when active
                    if voiceLoop.isActive {
                        VStack(spacing: 4) {
                            Text("Live: '\(voiceLoop.currentTranscript)'")
                                .font(.caption)
                                .foregroundColor(.green)
                            if let stt = voiceLoop.speechRecognition, !stt.lastError.isEmpty {
                                Text("ERROR: \(stt.lastError)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // Microphone button
                Button(action: toggleVoice) {
                    ZStack {
                        Circle()
                            .fill(voiceLoop.isActive ? Color.red : Color.blue)
                            .frame(width: 200, height: 200)
                            .shadow(radius: 10)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                // Transcript display
                if !voiceLoop.lastTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You said:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(voiceLoop.lastTranscript)
                            .font(.body)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }

                // Response display
                if !voiceLoop.lastResponse.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(voiceLoop.lastResponse)
                            .font(.body)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }

                // Debug log with file contents button
                VStack(spacing: 8) {
                    Button("Show Debug File") {
                        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("debug.log"),
                           let contents = try? String(contentsOf: url) {
                            voiceLoop.debugLog = contents.components(separatedBy: "\n")
                        }
                    }
                    .buttonStyle(.bordered)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(voiceLoop.debugLog.enumerated()), id: \.offset) { _, log in
                                Text(log)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.5))
                    }
                    .frame(height: 150)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
        .task {
            isHealthy = await voiceLoop.checkConnection()
        }
        .sheet(isPresented: $showVoicePicker) {
            VoiceSelector(selectedVoice: $selectedVoice)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(selectedVoice: $selectedVoice)
        }
        .onChange(of: selectedVoice) { _, newVoice in
            Config.selectedVoice = newVoice
            // Reconnect with new voice if active
            if voiceLoop.isActive {
                voiceLoop.stop()
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await voiceLoop.start()
                }
            }
        }
        .alert("Error", isPresented: .constant(voiceLoop.error != nil)) {
            Button("OK") {
                voiceLoop.error = nil
            }
        } message: {
            Text(voiceLoop.error ?? "Unknown error")
        }
    }

    // MARK: - Actions

    private func toggleVoice() {
        if voiceLoop.isActive {
            voiceLoop.stop()
        } else {
            Task {
                await voiceLoop.start()
            }
        }
    }

    // MARK: - UI State

    private var statusIcon: String {
        if voiceLoop.isInitializing {
            return "hourglass"
        }
        if !isHealthy {
            return "exclamationmark.triangle.fill"
        }
        return voiceLoop.isActive ? "waveform" : "moon.zzz.fill"
    }

    private var statusColor: Color {
        if voiceLoop.isInitializing {
            return .blue
        }
        if !isHealthy {
            return .orange
        }
        return voiceLoop.isActive ? .green : .gray
    }

    private var statusText: String {
        if voiceLoop.isInitializing {
            return "Initializing..."
        }
        if !isHealthy {
            return "Cannot reach SoniqueBar"
        }
        return voiceLoop.isActive ? "Listening..." : "Tap to start"
    }
}

#Preview {
    ContentView()
}
