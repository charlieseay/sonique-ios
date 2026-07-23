import Foundation

/// Supported LLM providers
enum LLMProvider: String, Codable, CaseIterable {
    case claude = "Claude"
    case chatgpt = "ChatGPT"
    case gemini = "Gemini"
    case ollama = "Ollama (Local)"

    var displayName: String { rawValue }

    var authURL: URL {
        switch self {
        case .claude:
            return URL(string: "https://claude.ai/login")!
        case .chatgpt:
            return URL(string: "https://chat.openai.com/auth/login")!
        case .gemini:
            return URL(string: "https://gemini.google.com")!
        case .ollama:
            return URL(string: "http://localhost:11434")!
        }
    }

    var chatURL: URL {
        switch self {
        case .claude:
            return URL(string: "https://claude.ai/new")!
        case .chatgpt:
            return URL(string: "https://chat.openai.com")!
        case .gemini:
            return URL(string: "https://gemini.google.com/app")!
        case .ollama:
            return URL(string: "http://localhost:11434")!
        }
    }
}

/// Manages LLM provider configuration and session state
@MainActor
class ProviderManager: ObservableObject {
    static let shared = ProviderManager()

    // Current active provider
    @Published var activeProvider: LLMProvider? {
        didSet {
            if let provider = activeProvider {
                UserDefaults.standard.set(provider.rawValue, forKey: "active_provider")
            } else {
                UserDefaults.standard.removeObject(forKey: "active_provider")
            }
        }
    }

    // Setup completion state
    @Published var isConfigured: Bool = false

    private init() {
        // Load active provider from UserDefaults
        if let providerString = UserDefaults.standard.string(forKey: "active_provider"),
           let provider = LLMProvider(rawValue: providerString) {
            self.activeProvider = provider
        }

        // Update state async
        Task { @MainActor in
            await self.updateConfiguredState()
        }
    }

    /// Check if current provider has valid session
    func hasValidSession(for provider: LLMProvider) -> Bool {
        switch provider {
        case .claude:
            return ClaudeSessionManager.shared.isValid
        case .chatgpt:
            // TODO: Implement ChatGPTSessionManager
            return false
        case .gemini:
            // TODO: Implement GeminiSessionManager
            return false
        case .ollama:
            // TODO: Check if Ollama is running
            return false
        }
    }

    /// Update configured state based on active provider
    func updateConfiguredState() async {
        guard let provider = activeProvider else {
            isConfigured = false
            return
        }

        isConfigured = hasValidSession(for: provider)
    }

    /// Set active provider and update state
    func setActiveProvider(_ provider: LLMProvider) async {
        activeProvider = provider
        await updateConfiguredState()
    }

    /// Query current provider
    func query(_ prompt: String) async throws -> String {
        guard let provider = activeProvider else {
            throw ProviderError.noProviderConfigured
        }

        guard hasValidSession(for: provider) else {
            throw ProviderError.sessionExpired
        }

        switch provider {
        case .claude:
            return try await ClaudeSessionManager.shared.query(prompt)
        case .chatgpt:
            throw ProviderError.notImplemented("ChatGPT support coming soon")
        case .gemini:
            throw ProviderError.notImplemented("Gemini support coming soon")
        case .ollama:
            throw ProviderError.notImplemented("Ollama support coming soon")
        }
    }
}

enum ProviderError: LocalizedError {
    case noProviderConfigured
    case sessionExpired
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No LLM provider configured. Please complete setup."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .notImplemented(let message):
            return message
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let providerReauthRequired = Notification.Name("providerReauthRequired")
    static let providerSessionRestored = Notification.Name("providerSessionRestored")
}
