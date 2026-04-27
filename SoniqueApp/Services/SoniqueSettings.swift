import SwiftUI
import Combine

/// `AppStorage` / `UserDefaults` keys for LLM routing UI (CAAL `settings.json` / `.env` parity in task #284).
enum LLMRoutingStorageKeys {
    static let llmProvider = "llmProvider"
    static let preferredModelLabel = "preferredModelLabel"
    static let fallbackPolicy = "fallbackPolicy"
    static let nvidiaFeatureEnabled = "nvidiaFeatureEnabled"
    static let nvidiaBaseURL = "nvidiaBaseURL"
}

enum SoniqueLLMProvider: String, CaseIterable, Identifiable {
    case ollama
    case nvidia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama (Local)"
        case .nvidia: return "NVIDIA NIM (preview)"
        }
    }
}

enum SoniqueFallbackPolicy: String, CaseIterable, Identifiable {
    case localOnly = "local_only"
    case providerThenLocal = "provider_then_local"
    case localThenProvider = "local_then_provider"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localOnly: return "Local only"
        case .providerThenLocal: return "Provider then local"
        case .localThenProvider: return "Local then provider"
        }
    }

    /// Short hint for settings / status (routing behavior is enforced in CAAL — task #284).
    var routingHint: String {
        switch self {
        case .localOnly:
            return "When wired: use only the local stack (e.g. Ollama)."
        case .providerThenLocal:
            return "When wired: try NVIDIA NIM first when enabled, then local."
        case .localThenProvider:
            return "When wired: try local first, then NVIDIA NIM if needed."
        }
    }
}

class SoniqueSettings: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("apiKey") var apiKey: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("externalURL") var externalURL: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("extendedSession") var extendedSession: Bool = false {
        didSet { objectWillChange.send() }
    }
    @AppStorage(LLMRoutingStorageKeys.llmProvider) var llmProviderRaw: String = SoniqueLLMProvider.ollama.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage(LLMRoutingStorageKeys.preferredModelLabel) var preferredModelLabel: String = "gemma4" {
        didSet { objectWillChange.send() }
    }
    @AppStorage(LLMRoutingStorageKeys.fallbackPolicy) var fallbackPolicyRaw: String = SoniqueFallbackPolicy.localOnly.rawValue {
        didSet { objectWillChange.send() }
    }
    @AppStorage(LLMRoutingStorageKeys.nvidiaFeatureEnabled) var nvidiaFeatureEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }
    @AppStorage(LLMRoutingStorageKeys.nvidiaBaseURL) var nvidiaBaseURL: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("hasCompletedSetup") var hasCompletedSetup: Bool = false

    var llmProvider: SoniqueLLMProvider {
        get {
            let decoded = SoniqueLLMProvider(rawValue: llmProviderRaw) ?? .ollama
            if !nvidiaFeatureEnabled, decoded == .nvidia { return .ollama }
            return decoded
        }
        set { llmProviderRaw = newValue.rawValue }
    }

    var fallbackPolicy: SoniqueFallbackPolicy {
        get { SoniqueFallbackPolicy(rawValue: fallbackPolicyRaw) ?? .localOnly }
        set { fallbackPolicyRaw = newValue.rawValue }
    }

    var availableProviders: [SoniqueLLMProvider] {
        nvidiaFeatureEnabled ? SoniqueLLMProvider.allCases : [.ollama]
    }

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var normalizedServerURL: String {
        var url = serverURL.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }

    var normalizedExternalURL: String {
        var url = externalURL.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }
}
