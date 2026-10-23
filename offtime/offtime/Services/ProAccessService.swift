import Foundation
import Combine
import StoreKit
import os

enum ProAccessSource: String {
    case free
    case purchase
}

enum ProAccessPolicy {
    static let productID = "offtime.pro.lifetime"
}

@MainActor
final class ProAccessService: ObservableObject {
    @Published private(set) var source: ProAccessSource = .free
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasAttemptedProductLoad = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var statusMessage: String?

    var isUnlocked: Bool { source != .free }
    var isProcessing: Bool { isPurchasing || isRestoring }
    var priceText: String? { product?.displayPrice }
    var displayTitle: String {
        product?.displayName ?? "\(AppDisplay.name) Pro"
    }
    private let logger = Logger(subsystem: "lt.offtime", category: "ProAccess")
    private var transactionListener: Task<Void, Never>?
    private let defaults: UserDefaults
    private let sourceKey = "pro_access_source"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawValue = defaults.string(forKey: sourceKey) {
            if let storedSource = ProAccessSource(rawValue: rawValue) {
                source = storedSource
            } else {
                defaults.removeObject(forKey: sourceKey)
            }
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func load() async {
        startTransactionListener()
        async let entitlements: Void = refreshEntitlementsWithRetry()
        async let products: Void = loadProducts()
        _ = await (entitlements, products)
    }

    private func refreshEntitlementsWithRetry() async {
        if await refreshEntitlements() { return }

        for delay in [Duration.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)] {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            if await refreshEntitlements() { return }
        }
    }

    func refreshProductsIfNeeded() async {
        guard product == nil else { return }
        await loadProducts()
    }

    func reloadProducts() async {
        await loadProducts()
    }

    private func loadProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        defer {
            isLoadingProducts = false
            hasAttemptedProductLoad = true
        }

        do {
            let products = try await Product.products(for: [ProAccessPolicy.productID])
            product = products.first { $0.id == ProAccessPolicy.productID }

            if product == nil {
                let storefront = await Storefront.current
                logger.error(
                    "Pro product missing; storefront=\(storefront?.countryCode ?? "unknown", privacy: .public), count=\(products.count, privacy: .public)"
                )
            }
        } catch {
            logger.error("Failed to load Pro product: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase() async {
        guard !isProcessing else { return }

        guard let product else {
            statusMessage = String(localized: "pro.product.unavailable")
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    if isUnlocked {
                        statusMessage = String(localized: "pro.purchase.success")
                    } else {
                        statusMessage = String(localized: "pro.purchase.failed")
                    }
                } else {
                    statusMessage = String(localized: "pro.purchase.failed")
                }
            case .userCancelled:
                break
            case .pending:
                statusMessage = String(localized: "pro.purchase.pending")
            @unknown default:
                statusMessage = String(localized: "pro.purchase.failed")
            }
        } catch {
            logger.error("Pro purchase failed: \(error.localizedDescription)")
            statusMessage = String(localized: "pro.purchase.failed")
        }
    }

    func restore() async {
        guard !isProcessing else { return }

        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            let restored = await refreshEntitlements()
            statusMessage = restored
                ? String(localized: "pro.restore.success")
                : String(localized: "pro.restore.empty")
        } catch {
            logger.error("Pro restore failed: \(error.localizedDescription, privacy: .public)")
            let restored = await refreshEntitlements()
            statusMessage = restored
                ? String(localized: "pro.restore.success")
                : String(localized: "pro.restore.failed")
        }

        if product == nil {
            await loadProducts()
        }
    }

    private func startTransactionListener() {
        guard transactionListener == nil else { return }

        transactionListener = Task { [weak self] in
            for await verification in Transaction.updates {
                await self?.handleTransactionVerification(verification)
            }
        }
    }

    @discardableResult
    func refreshEntitlements() async -> Bool {
        var hasPurchase = false

        for await verification in Transaction.currentEntitlements {
            switch verification {
            case .verified(let transaction):
                guard transaction.productID == ProAccessPolicy.productID else { continue }
                guard transaction.revocationDate == nil else {
                    logger.info("Pro entitlement revoked at \(transaction.revocationDate?.ISO8601Format() ?? "unknown", privacy: .public)")
                    continue
                }

                hasPurchase = true
                logger.info(
                    "Pro entitlement: env=\(transaction.environment.rawValue, privacy: .public) store=\(transaction.storefront.countryCode, privacy: .public) own=\(transaction.ownershipType.rawValue, privacy: .public) date=\(transaction.purchaseDate.ISO8601Format(), privacy: .public)"
                )
                break
            case .unverified(_, let error):
                logger.error("Unverified Pro entitlement: \(error.localizedDescription, privacy: .public)")
            }
        }

        if hasPurchase {
            source = .purchase
            defaults.set(source.rawValue, forKey: sourceKey)
        } else if source == .purchase {
            source = .free
            defaults.set(source.rawValue, forKey: sourceKey)
        }

        logger.info("Pro source=\(self.source.rawValue, privacy: .public), hasPurchase=\(hasPurchase, privacy: .public)")
        return hasPurchase
    }

    private func handleTransactionVerification(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification,
              transaction.productID == ProAccessPolicy.productID else { return }

        await transaction.finish()
        await refreshEntitlements()
    }
}
