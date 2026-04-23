import StoreKit
import Foundation

@MainActor
class PremiumManager: ObservableObject {
    static let removeAdsProductID = "com.seayniclabs.sonique.removeads"
    static weak var shared: PremiumManager?

    @Published private(set) var isPremium = false
    @Published private(set) var product: Product?
    @Published var isPurchasing = false
    @Published var isRestoring = false

    private var transactionListener: Task<Void, Never>?

    init() {
        PremiumManager.shared = self
        transactionListener = listenForTransactions()
        Task { await refresh() }
    }

    deinit { transactionListener?.cancel() }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                isPremium = true
            }
        } catch {}
    }

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        try? await AppStore.sync()
        await refresh()
    }

    // MARK: - Private

    private func refresh() async {
        if let products = try? await Product.products(for: [Self.removeAdsProductID]) {
            product = products.first
        }
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == Self.removeAdsProductID,
               t.revocationDate == nil {
                isPremium = true
                return
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result,
                   t.productID == Self.removeAdsProductID {
                    await t.finish()
                    await MainActor.run { self?.isPremium = true }
                }
            }
        }
    }
}
