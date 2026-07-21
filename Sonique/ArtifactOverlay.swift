import SwiftUI

/// Ephemeral full-screen image overlay (Snapchat-style). Shows an image the assistant
/// produced (e.g. a Mac screenshot), staying on screen until the user taps the close
/// button or the conversation organically advances (VoiceLoop clears artifactURL).
struct ArtifactOverlay: View {
    let url: URL
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            } else if loading {
                ProgressView().tint(.white)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                    Text("Couldn't load the image.").font(.subheadline)
                }
                .foregroundColor(.white.opacity(0.7))
            }

            // Close button — top-right, 44pt target
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 4)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close image")
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        // Tap anywhere outside to dismiss as well.
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .task(id: url) { await load() }
    }

    private func load() async {
        loading = true; failed = false; image = nil
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let img = UIImage(data: data) else {
                failed = true; loading = false; return
            }
            image = img
            loading = false
        } catch {
            failed = true; loading = false
        }
    }
}
