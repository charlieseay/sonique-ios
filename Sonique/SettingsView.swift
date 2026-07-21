import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = ""
    @AppStorage("useTailscale") private var useTailscale = false
    @AppStorage("tts_provider") private var ttsProvider = "elevenlabs"
    @AppStorage("interruption_threshold") private var interruptionThreshold: Double = 0.4

    @State private var connectionTestResult: String?
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (Build \(build))"
    }

    private var effectiveServerURL: String {
        if serverURL.isEmpty {
            return useTailscale ? Config.tailscaleURL : Config.defaultLANURL
        }
        return serverURL
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

                    Text("Default: \(Config.defaultLANURL) (LAN) or \(Config.defaultTailscaleURL) (Tailscale)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Auth Token", text: Binding(
                        get: { UserDefaults.standard.string(forKey: "authToken") ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: "authToken") }
                    ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    Text("Required for SoniqueBar authentication. Default: 5FA5EE09-442D-4969-B091-9AC331E1C39C")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Voice")) {
                    LabeledContent("Current Voice", value: Config.selectedVoiceName)
                    Text("Change the voice from the waveform button on the main screen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Interruption Sensitivity")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Threshold: \(interruptionThreshold, specifier: "%.2f")")
                                .font(.subheadline)
                            Spacer()
                        }

                        Slider(value: $interruptionThreshold, in: 0.0...1.0, step: 0.05)

                        HStack {
                            Text("Lenient")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Aggressive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("Lower = more backchannels ignored (\"mm-hmm\" won't interrupt). Higher = more sensitive to any speech.")
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
                        Label("Kokoro via SoniqueBar on your Mac (LAN/Tailscale)", systemImage: "checkmark.circle.fill")
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

                    if let result = connectionTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.hasPrefix("✓") ? .green : .red)
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
                let testURL = serverURL.isEmpty ? Config.defaultLANURL : serverURL
                guard let url = URL(string: "\(testURL)/health") else {
                    await MainActor.run { connectionTestResult = "Invalid URL: \(testURL)" }
                    return
                }

                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run { connectionTestResult = "Not an HTTP response" }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    await MainActor.run { connectionTestResult = "Failed: HTTP \(httpResponse.statusCode)" }
                    return
                }

                // Check JSON
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    await MainActor.run { connectionTestResult = "Invalid JSON response" }
                    return
                }

                await MainActor.run { connectionTestResult = "✓ Connected! Status: \(status)" }
            } catch {
                await MainActor.run { connectionTestResult = "Error: \(error.localizedDescription)" }
            }
        }
    }
}
