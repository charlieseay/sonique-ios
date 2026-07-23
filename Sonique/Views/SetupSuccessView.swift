import SwiftUI

/// Success screen shown after completing authentication
struct SetupSuccessView: View {
    @Environment(\.dismiss) var dismiss
    @State private var testQueryResponse: String?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Success animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .symbolEffect(.bounce)
            }

            Text("You're All Set!")
                .font(.largeTitle)
                .bold()

            Text("Quinn is connected and ready to help")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Test it section
            VStack(spacing: 16) {
                Divider()
                    .padding(.vertical)

                Text("Try It Now")
                    .font(.headline)

                if isTesting {
                    ProgressView()
                        .padding()
                } else if let response = testQueryResponse {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.blue)
                            Text("Quinn says:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(response)
                            .font(.body)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .transition(.opacity)
                } else {
                    Button(action: runTestQuery) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Ask Quinn a Test Question")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()

            // Next steps
            VStack(spacing: 12) {
                Text("What's Next?")
                    .font(.headline)

                QuickTipRow(
                    icon: "mic.fill",
                    text: "Say \"Hey Quinn\" to activate"
                )

                QuickTipRow(
                    icon: "gear",
                    text: "Customize settings anytime"
                )

                QuickTipRow(
                    icon: "questionmark.circle",
                    text: "Ask anything - Quinn has lots of skills"
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 20)

            Button(action: {
                dismiss()
            }) {
                Text("Start Using Quinn")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private func runTestQuery() {
        isTesting = true

        // Send a simple test query to verify everything works
        Task {
            do {
                let response = try await ProviderManager.shared.query("Tell me a fun fact in one sentence")

                await MainActor.run {
                    withAnimation {
                        testQueryResponse = response
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        testQueryResponse = "Hmm, something went wrong. Please check your connection and try again."
                        isTesting = false
                    }
                }
            }
        }
    }
}

struct QuickTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }
}

#Preview {
    SetupSuccessView()
}
