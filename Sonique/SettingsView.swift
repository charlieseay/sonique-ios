import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://192.168.0.221:8890"
    @AppStorage("useTailscale") private var useTailscale = false

    @Binding var selectedVoice: ElevenLabsVoice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Connection")) {
                    Toggle("Use Tailscale", isOn: $useTailscale)
                        .onChange(of: useTailscale) { _, newValue in
                            if newValue {
                                serverURL = Config.tailscaleURL
                            } else {
                                serverURL = "http://192.168.0.221:8890"
                            }
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
                    ForEach(ElevenLabsVoice.allCases) { voice in
                        Button(action: {
                            selectedVoice = voice
                            Config.selectedVoice = voice
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(voice.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(voice.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedVoice == voice {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(header: Text("About")) {
                    LabeledContent("App Version", value: "1.0 (Build 36)")
                    LabeledContent("Voice Provider", value: "ElevenLabs")
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
