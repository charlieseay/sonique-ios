import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var showingAuth = false
    @State private var selectedProvider: LLMProvider?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        TabView(selection: $currentStep) {
            // Step 1: Welcome
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse)

                Text("Meet Quinn")
                    .font(.largeTitle)
                    .bold()

                Text("Your AI voice assistant with superpowers")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button(action: {
                    withAnimation {
                        currentStep = 1
                    }
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .tag(0)

            // Step 2: Provider Selection
            VStack(spacing: 20) {
                Text("Connect Your AI")
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 40)

                Text("Quinn works with your existing AI subscription")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    ProviderButton(
                        provider: .claude,
                        recommended: true,
                        action: {
                            selectedProvider = .claude
                            showingAuth = true
                        }
                    )

                    ProviderButton(
                        provider: .chatgpt,
                        action: {
                            selectedProvider = .chatgpt
                            showingAuth = true
                        }
                    )

                    ProviderButton(
                        provider: .gemini,
                        action: {
                            selectedProvider = .gemini
                            showingAuth = true
                        }
                    )

                    Button(action: {
                        selectedProvider = .ollama
                        showingAuth = true
                    }) {
                        Text("Advanced: Local Ollama")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)

                Spacer()

                Button("Back") {
                    withAnimation {
                        currentStep = 0
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
            }
            .tag(1)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .sheet(isPresented: $showingAuth) {
            if let provider = selectedProvider {
                LLMAuthView(
                    provider: provider,
                    isPresented: $showingAuth,
                    onSuccess: {
                        dismiss()
                    }
                )
            }
        }
    }
}

struct ProviderButton: View {
    let provider: LLMProvider
    var recommended: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if recommended {
                            Text("RECOMMENDED")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    var iconName: String {
        switch provider {
        case .claude:
            return "brain"
        case .chatgpt:
            return "bubble.left.and.bubble.right"
        case .gemini:
            return "sparkles"
        case .ollama:
            return "server.rack"
        }
    }

    var description: String {
        switch provider {
        case .claude:
            return "Best for reasoning and coding"
        case .chatgpt:
            return "Fast and conversational"
        case .gemini:
            return "Google's AI assistant"
        case .ollama:
            return "Run AI models on your device"
        }
    }
}

#Preview {
    OnboardingView()
}
