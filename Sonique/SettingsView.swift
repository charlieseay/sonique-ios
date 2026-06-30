import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://192.168.0.221:8890"
    @AppStorage("useTailscale") private var useTailscale = false
    @AppStorage("tts_provider") private var ttsProvider = "elevenlabs"

    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (Build \(build))"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Connection")) {
                    Toggle("Use Tailscale", isOn: $useTailscale)
                        .onChange(of: useTailscale) { _, newValue in
                            if newValue {
                                serverURL = Config.tailscaleURL
                            } else {
                                serverURL = Config.defaultLANURL
                            }
                            // Also update Config to keep in sync
                            Config.tailscaleFallbackEnabled = newValue
                        }

                    TextField("Server URL", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Text("Default: http://192.168.0.221:8890 (LAN)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Voice")) {
                    LabeledContent("Current Voice", value: Config.selectedVoiceName)
                    Text("Change the voice from the waveform button on the main screen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("TTS Provider")) {
                    Picker("Provider", selection: $ttsProvider) {
                        Text("ElevenLabs (Cloud)").tag("elevenlabs")
                        Text("Kokoro (Local)").tag("kokoro")
                    }
                    .pickerStyle(.segmented)

                    if ttsProvider == "kokoro" {
                        Label("Using embedded TTS on Mac", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Label("Using ElevenLabs cloud API", systemImage: "cloud.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }

                Section(header: Text("About")) {
                    LabeledContent("App Version", value: appVersion)
                    LabeledContent("TTS Provider", value: ttsProvider == "kokoro" ? "Kokoro (Local)" : "ElevenLabs")
                    LabeledContent("Brain", value: "SoniqueBar (Mac)")
                }

                Section {
                    Button(action: testConnection) {
                        Label("Test Connection", systemImage: "network")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func testConnection() {
        Task {
            do {
                guard let url = URL(string: "\(serverURL)/health") else { return }

                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[Settings] Connection test failed: bad status")
                    return
                }

                print("[Settings] Connection test succeeded")
            } catch {
                print("[Settings] Connection test failed: \(error)")
            }
        }
    }
}
