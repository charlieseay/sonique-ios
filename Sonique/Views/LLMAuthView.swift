import SwiftUI
import WebKit
import AuthenticationServices

struct LLMAuthView: View {
    let provider: LLMProvider
    @Binding var isPresented: Bool
    let onSuccess: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Opening Safari...")
                            .font(.headline)

                        Text("Sign in to \(provider.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)

                        Text("Authentication Failed")
                            .font(.headline)

                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            errorMessage = nil
                            startAuthSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: provider == .claude ? "brain" : "bubble.left.and.bubble.right")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Sign in to \(provider.displayName)")
                            .font(.title2)
                            .bold()

                        Text("Safari will open for secure authentication")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Continue") {
                            startAuthSession()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }

                Spacer()
            }
            .navigationTitle("Authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        authSession?.cancel()
                        isPresented = false
                    }
                }
            }
        }
    }

    private func handleAuthSuccess(cookies: [HTTPCookie]) {
        // Save cookies to session manager
        Task { @MainActor in
            do {
                try await ClaudeSessionManager.shared.saveSession(cookies: cookies)

                // Set as active provider
                await ProviderManager.shared.setActiveProvider(provider)

                // Success - show success screen, then dismiss
                // Note: Success screen will be shown by the parent (OnboardingView)
                isPresented = false
                onSuccess()

            } catch {
                errorMessage = "Failed to save session: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

struct WebAuthView: UIViewRepresentable {
    let provider: LLMProvider
    let onLoadingStateChange: (Bool) -> Void
    let onSuccess: ([HTTPCookie]) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Enable JavaScript
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Load provider auth URL
        let request = URLRequest(url: provider.authURL)
        webView.load(request)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebAuthView
        private var hasCheckedAuth = false

        init(_ parent: WebAuthView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingStateChange(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingStateChange(false)

            // Check if user is authenticated (URL changed to chat/new page)
            guard let url = webView.url?.absoluteString else { return }

            let isAuthenticated: Bool = {
                switch parent.provider {
                case .claude:
                    return url.contains("/new") || url.contains("/chat")
                case .chatgpt:
                    return url.contains("chat.openai.com") && !url.contains("/auth/")
                case .gemini:
                    return url.contains("/app") || url.contains("/chat")
                case .ollama:
                    return true // Local, no auth needed
                }
            }()

            if isAuthenticated && !hasCheckedAuth {
                hasCheckedAuth = true
                extractCookies(from: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingStateChange(false)
            parent.onError(error.localizedDescription)
        }

        private func extractCookies(from webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                // Filter to only provider-relevant cookies
                let relevantCookies = cookies.filter { cookie in
                    switch self.parent.provider {
                    case .claude:
                        return cookie.domain.contains("claude.ai")
                    case .chatgpt:
                        return cookie.domain.contains("openai.com")
                    case .gemini:
                        return cookie.domain.contains("google.com")
                    case .ollama:
                        return cookie.domain.contains("localhost")
                    }
                }

                if !relevantCookies.isEmpty {
                    self.parent.onSuccess(relevantCookies)
                } else {
                    self.parent.onError("No authentication cookies found")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true

    LLMAuthView(
        provider: .claude,
        isPresented: $isPresented,
        onSuccess: {
            print("Auth success!")
        }
    )
}
