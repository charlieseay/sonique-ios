import SwiftUI

struct ContentView: View {
    @StateObject private var voiceLoop = VoiceLoop()
    @State private var isHealthy = false

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
                // Status
                VStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 40))
                        .foregroundColor(statusColor)

                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(.secondary)
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

                Spacer()

                // Character usage
                Text("\(voiceLoop.characterUsage) / 50,000 characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .task {
            isHealthy = await voiceLoop.checkConnection()
        }
    }

    // MARK: - Actions

    private func toggleVoice() {
        if voiceLoop.isActive {
            voiceLoop.stop()
        } else {
            voiceLoop.start()
        }
    }

    // MARK: - UI State

    private var statusIcon: String {
        if !isHealthy {
            return "exclamationmark.triangle.fill"
        }
        return voiceLoop.isActive ? "waveform" : "moon.zzz.fill"
    }

    private var statusColor: Color {
        if !isHealthy {
            return .orange
        }
        return voiceLoop.isActive ? .green : .gray
    }

    private var statusText: String {
        if !isHealthy {
            return "Cannot reach SoniqueBar"
        }
        return voiceLoop.isActive ? "Listening..." : "Tap to start"
    }
}

#Preview {
    ContentView()
}
