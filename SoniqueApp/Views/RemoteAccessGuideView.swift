import SwiftUI

struct RemoteAccessGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.soniqueBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        VStack(alignment: .leading, spacing: 8) {
                            Text("By default, Sonique only works on your home network. Add a Remote URL in settings to use it anywhere.")
                                .font(.subheadline)
                                .foregroundStyle(Color.soniqueSubtext)
                        }

                        optionCard(
                            title: "Tailscale (recommended)",
                            badge: "Free",
                            icon: "lock.shield.fill",
                            description: "Install Tailscale on your Mac and iPhone. It creates a private network between your devices — no port forwarding, no firewall rules, nothing public.",
                            steps: [
                                "Install Tailscale on this Mac (tailscale.com)",
                                "Install Tailscale on your iPhone from the App Store",
                                "Sign in to the same account on both",
                                "Run: tailscale ip -4 to get your Mac's Tailscale IP",
                                "Set Remote URL to http://<tailscale-ip>:3000"
                            ],
                            url: "https://tailscale.com/download"
                        )

                        optionCard(
                            title: "Twingate",
                            badge: "Free",
                            icon: "network.badge.shield.half.filled",
                            description: "Similar to Tailscale — a zero-trust private network connector. Good if you already use it for work.",
                            steps: [
                                "Sign up at twingate.com",
                                "Install the Twingate connector on your Mac",
                                "Install the Twingate client on your iPhone",
                                "Add your Mac as a resource",
                                "Set Remote URL to http://<twingate-resource-ip>:3000"
                            ],
                            url: "https://www.twingate.com"
                        )

                        optionCard(
                            title: "Cloudflare Tunnel",
                            badge: "Free",
                            icon: "cloud.fill",
                            description: "Exposes your local server over a public HTTPS URL. Good if you want HTTPS without any certificate setup, but your URL is technically public (protected by Cloudflare Access).",
                            steps: [
                                "Install cloudflared on your Mac (brew install cloudflared)",
                                "Run: cloudflared tunnel login",
                                "Run: cloudflared tunnel create sonique",
                                "Configure the tunnel to forward port 3000",
                                "Set Remote URL to your tunnel's https:// URL"
                            ],
                            url: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/"
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Already set up?")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.soniqueText)
                            Text("Enter your remote address in Settings → Remote URL, then test the connection.")
                                .font(.caption)
                                .foregroundStyle(Color.soniqueSubtext)
                        }
                        .padding()
                        .background(Color.soniqueSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                }
            }
            .navigationTitle("Remote Access")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.soniqueAccent2)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func optionCard(title: String, badge: String, icon: String,
                             description: String, steps: [String], url: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.soniqueAccent2)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.soniqueText)
                Spacer()
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.soniqueAccent2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.soniqueAccent2.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.soniqueSubtext)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.soniqueAccent2)
                            .frame(width: 16)
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(Color.soniqueSubtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Link("Set up \(title) →", destination: URL(string: url)!)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.soniqueAccent2)
        }
        .padding()
        .background(Color.soniqueSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
