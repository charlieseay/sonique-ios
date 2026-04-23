import SwiftUI
import GoogleMobileAds

private let bannerAdUnitID = "ca-app-pub-4659753545106426/6599049626"

// MARK: - Public banner view — hidden automatically for premium users

struct AdBannerView: View {
    @EnvironmentObject private var premium: PremiumManager
    @State private var showUpgrade = false

    var body: some View {
        if !premium.isPremium {
            VStack(spacing: 0) {
                BannerAdContainer()
                    .frame(height: 50)
                removeAdsStrip
            }
            .sheet(isPresented: $showUpgrade) {
                UpgradeView().environmentObject(premium)
            }
        }
    }

    private var removeAdsStrip: some View {
        HStack {
            Spacer()
            Button("Remove Ads — $2.99") { showUpgrade = true }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.soniqueSubtext)
                .padding(.vertical, 3)
            Spacer()
        }
        .background(Color.soniqueBackground)
    }
}

// MARK: - UIKit wrapper for GADBannerView

private struct BannerAdContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = bannerAdUnitID
        banner.rootViewController = context.coordinator.rootViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        func rootViewController() -> UIViewController? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.rootViewController
        }
    }
}

// MARK: - Upgrade sheet

struct UpgradeView: View {
    @EnvironmentObject private var premium: PremiumManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.soniqueBackground.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(
                            colors: [.soniqueAccent, .soniqueAccent2],
                            startPoint: .topLeading, endPoint: .bottomTrailing))

                    VStack(spacing: 8) {
                        Text("Sonique Premium")
                            .font(.title2.bold())
                            .foregroundStyle(Color.soniqueText)
                        Text(premium.product.map { $0.displayPrice } ?? "$2.99")
                            .font(.title3)
                            .foregroundStyle(Color.soniqueAccent2)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        featureRow(icon: "globe",       text: "Remote access — use Sonique anywhere, not just at home")
                        featureRow(icon: "xmark.circle", text: "No ads")
                        featureRow(icon: "heart.fill",  text: "Support independent development")
                    }
                    .padding(.horizontal, 32)

                    VStack(spacing: 12) {
                        Button {
                            Task { await premium.purchase() }
                        } label: {
                            Group {
                                if premium.isPurchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Unlock Premium")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.soniqueAccent2)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(premium.isPurchasing || premium.isRestoring)

                        Button {
                            Task { await premium.restore() }
                        } label: {
                            Group {
                                if premium.isRestoring {
                                    ProgressView().scaleEffect(0.7).tint(.soniqueSubtext)
                                } else {
                                    Text("Restore Purchase")
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.soniqueSubtext)
                        }
                        .disabled(premium.isPurchasing || premium.isRestoring)
                    }
                    .padding(.horizontal, 24)

                    Text("Ads help keep Sonique free. One-time purchase — no subscription.")
                        .font(.caption)
                        .foregroundStyle(Color.soniqueSubtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(Color.soniqueSubtext)
                }
            }
            .onChange(of: premium.isPremium) { _, newValue in
                if newValue { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.soniqueAccent2)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.soniqueSubtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
