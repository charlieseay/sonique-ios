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

    private func startAuthSession() {
        isLoading = true
        errorMessage = nil

        // Use ASWebAuthenticationSession - shares cookies with Safari
        // Callback URL scheme - we just need any valid URL to detect completion
        let callbackScheme = "sonique"

        authSession = ASWebAuthenticationSession(
            url: provider.authURL,
            callbackURLScheme: callbackScheme
        ) { callbackURL, error in
            isLoading = false

            if let error = error {
                // User cancelled or error occurred
                if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    errorMessage = "Authentication error: \(error.localizedDescription)"
                }
                return
            }

            // Auth completed - now extract cookies from shared cookie storage
            Task { @MainActor in
                await extractCookiesFromSharedStorage()
            }
        }

        // Present the session
        authSession?.prefersEphemeralWebBrowserSession = false // Share cookies with Safari
        authSession?.start()
    }

    private func extractCookiesFromSharedStorage() async {
        // Get cookies from HTTPCookieStorage (shared with Safari)
        let cookieStorage = HTTPCookieStorage.shared
        guard let allCookies = cookieStorage.cookies else {
            errorMessage = "No cookies found"
            return
        }

        // Filter to provider-specific cookies
        let relevantCookies = allCookies.filter { cookie in
            switch provider {
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

        if relevantCookies.isEmpty {
            errorMessage = "No \(provider.displayName) cookies found. Please try signing in again."
            return
        }

        // Save cookies
        do {
            try await ClaudeSessionManager.shared.saveSession(cookies: relevantCookies)
            await ProviderManager.shared.setActiveProvider(provider)

            isPresented = false
            onSuccess()
        } catch {
            errorMessage = "Failed to save session: \(error.localizedDescription)"
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
