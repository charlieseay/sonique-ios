import SwiftUI
import PhotosUI

/// Lets the user name their assistant (the name becomes the wake word) and set a
/// profile photo. Default name is "Sonique"; Charlie sets his to "Cael".
struct AssistantSettingsView: View {
    @ObservedObject private var profile = AssistantProfile.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""
    @State private var photoItem: PhotosPickerItem?

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
            }
            .navigationTitle("Your Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitName(); dismiss() }
                }
            }
            .onAppear { draftName = profile.name }
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
    }
}
