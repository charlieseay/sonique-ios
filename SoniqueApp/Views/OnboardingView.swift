import SwiftUI

/// First-run screen — shown when no server URL is configured.
struct OnboardingView: View {
    @EnvironmentObject private var settings: SoniqueSettings
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.soniqueBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo orb
                OrbView(sessionState: .idle, agentState: .idle)
                    .padding(.bottom, 40)

                // Copy
                VStack(spacing: 12) {
                    Text("sonique")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.soniqueAccent, .soniqueAccent2],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Text("Your voice. Your AI. Your server.")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.soniqueSubtext)
                }

                Spacer()

                // CTA
                VStack(spacing: 16) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Connect to Base Station", systemImage: "server.rack")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(LinearGradient.soniqueAccent, in: RoundedRectangle(cornerRadius: 16))
                    }

                    Text("Requires a running CAAL server on your local network.")
                        .font(.caption)
                        .foregroundStyle(Color.soniqueSubtext)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(SoniqueSettings())
        .environmentObject(SessionManager())
}
