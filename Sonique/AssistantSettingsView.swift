import SwiftUI
import PhotosUI

/// Lets the user name their assistant (the name becomes the wake word) and set a
/// profile photo. Default name is "Sonique"; Charlie sets his to "Cael".
@MainActor
struct AssistantSettingsView: View {
    @ObservedObject private var profile = AssistantProfile.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var lanURL: String = ""
    @State private var tailscaleURL: String = ""
    @State private var tailscaleOn: Bool = true

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                ZStack {
                                    if let img = profile.photo {
                                        Image(uiImage: img)
                                            .resizable().scaledToFill()
                                            .frame(width: 96, height: 96)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.purple.opacity(0.3))
                                            .frame(width: 96, height: 96)
                                            .overlay(Image(systemName: "waveform")
                                                .font(.system(size: 36))
                                                .foregroundColor(.white))
                                    }
                                    // Edit badge
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundColor(.accentColor)
                                        .background(Circle().fill(Color(.systemBackground)))
                                        .offset(x: 34, y: 34)
                                }
                            }
                            Text("Tap to change photo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section(header: Text("Assistant Name"),
                        footer: Text("This is what you'll say to wake your assistant. Default is “Sonique.”")) {
                    TextField("Sonique", text: $draftName)
                        .autocorrectionDisabled()
                        .onSubmit { commitName() }
                    if profile.wakeWord != draftName.lowercased().split(separator: " ").first.map(String.init) ?? "" {
                        Text("Wake word: “\(draftName.split(separator: " ").first.map(String.init) ?? draftName)”")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Connection"),
                        footer: Text("Sonique connects to SoniqueBar on your Mac. Use the local address on your home network, or turn on Tailscale fallback to reach it from anywhere.")) {
                    HStack {
                        Text("Mac (local)")
                        Spacer()
                        TextField(Config.defaultLANURL, text: $lanURL)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .foregroundColor(.secondary)
                    }
                    Toggle("Tailscale fallback", isOn: $tailscaleOn)
                    if tailscaleOn {
                        HStack {
                            Text("Tailscale")
                            Spacer()
                            TextField(Config.defaultTailscaleURL, text: $tailscaleURL)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Your Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitName(); dismiss() }
                }
            }
            .onAppear {
                draftName = profile.name
                lanURL = Config.commandServerURL
                tailscaleURL = Config.tailscaleURL
                tailscaleOn = Config.tailscaleFallbackEnabled
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        profile.photo = img
                    }
                }
            }
        }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = trimmed.isEmpty ? "Sonique" : trimmed
        // Persist connection settings too.
        let lan = lanURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Config.commandServerURL = lan.isEmpty ? Config.defaultLANURL : lan
        let ts = tailscaleURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Config.tailscaleURL = ts.isEmpty ? Config.defaultTailscaleURL : ts
        Config.tailscaleFallbackEnabled = tailscaleOn
    }
}
