import SwiftUI

/// Chat interface for text-based interaction with Quinn
struct ChatView: View {
    @ObservedObject var voiceLoop: VoiceLoop
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var messages: [(String, Bool)] = []  // (text, isUser)
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages scroll view
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                MessageBubble(text: message.0, isUser: message.1)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastIndex = messages.indices.last {
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Image preview (if attached)
                if let image = selectedImage {
                    HStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 80)
                            .cornerRadius(8)

                        Spacer()

                        Button(action: { selectedImage = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                // Input bar
                HStack(spacing: 12) {
                    Button(action: { showImagePicker = true }) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }

                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor((inputText.isEmpty && selectedImage == nil) ? .gray : .blue)
                    }
                    .disabled(inputText.isEmpty && selectedImage == nil)
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isInputFocused = true
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImage != nil else { return }

        let userMessage = trimmed.isEmpty ? "[Image]" : trimmed
        messages.append((userMessage, true))

        let textToSend = trimmed.isEmpty ? "What's in this image?" : trimmed
        let imageToSend = selectedImage

        inputText = ""
        selectedImage = nil

        // Send to backend - same /command/stream endpoint as voice
        Task {
            do {
                messages.append(("Thinking...", false))
                let thinkingIndex = messages.count - 1

                var response = ""

                if let image = imageToSend, let imageData = image.jpegData(compressionQuality: 0.8) {
                    // Send with image
                    let base64 = imageData.base64EncodedString()
                    for try await chunk in HTTPClient.sendCommandWithImage(textToSend, imageBase64: base64) {
                        if !chunk.text.isEmpty {
                            response += chunk.text
                            if messages.indices.contains(thinkingIndex) {
                                messages[thinkingIndex] = (response, false)
                            }
                        }
                    }
                } else {
                    // Text only
                    for try await chunk in HTTPClient.sendCommandStreaming(textToSend) {
                        if !chunk.text.isEmpty {
                            response += chunk.text
                            if messages.indices.contains(thinkingIndex) {
                                messages[thinkingIndex] = (response, false)
                            }
                        }
                    }
                }

                if response.isEmpty && messages.indices.contains(thinkingIndex) {
                    messages.remove(at: thinkingIndex)
                }

            } catch {
                messages.append(("Error: \(error.localizedDescription)", false))
            }
        }
    }
}

/// Message bubble for chat
struct MessageBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(text)
                .padding(12)
                .background(isUser ? Color.blue : Color(uiColor: .systemGray5))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

/// Image picker for photo/screenshot selection
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ChatView(voiceLoop: VoiceLoop())
}
