import Foundation
import Combine
import StoreKit
import os

enum ProAccessSource: String {
    case free
    case legacy
    case purchase
}

enum ProAccessPolicy {
    static let cityLimit = 4
    static let productID = "offtime.pro.lifetime"

    static func canAddCity(currentCount: Int, isUnlocked: Bool) -> Bool {
        isUnlocked || currentCount < cityLimit
    }

    static func isThemeUnlocked(_ mode: ThemeMode, isUnlocked: Bool) -> Bool {
        isUnlocked || mode == .system
    }
}

@MainActor
final class ProAccessService: ObservableObject {
    @Published private(set) var source: ProAccessSource = .free
    @Published private(set) var product: Product?
    @Published private(set) var isLoadingProducts = false
    @Published var statusMessage: String?

    var isUnlocked: Bool { source != .free }
    var isLegacyUnlocked: Bool { source == .legacy }
    var priceText: String { product?.displayPrice ?? String(localized: "pro.price.placeholder") }
    var displayTitle: String {
        product?.displayName ?? "\(AppDisplay.name) Pro"
    }
    private let logger = Logger(subsystem: "lt.offtime", category: "ProAccess")
    private var transactionListener: Task<Void, Never>?
    private let sourceKey = "pro_access_source"
    private let migrationKey = "pro_legacy_migration_completed"

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: sourceKey),
           let storedSource = ProAccessSource(rawValue: rawValue) {
            source = storedSource
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func migrateLegacyIfNeeded(hasExistingUserData: Bool) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        if LegacyProMigration.shouldUnlock(hasExistingUserData: hasExistingUserData) {
            source = .legacy
            UserDefaults.standard.set(source.rawValue, forKey: sourceKey)
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    func load() async {
        startTransactionListener()
        await refreshEntitlements()

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: [ProAccessPolicy.productID])
            product = products.first { $0.id == ProAccessPolicy.productID }
        } catch {
            logger.error("Failed to load Pro product: \(error.localizedDescription)")
        }
    }

    func purchase() async {
        guard let product else {
            statusMessage = String(localized: "pro.product.unavailable")
            return
        }

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
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isUnlocked
                ? String(localized: "pro.restore.success")
                : String(localized: "pro.restore.empty")
        } catch {
            logger.error("Pro restore failed: \(error.localizedDescription)")
            statusMessage = String(localized: "pro.restore.failed")
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

    private func refreshEntitlements() async {
        var hasPurchase = false

        for await verification in Transaction.currentEntitlements {
            if case .verified(let transaction) = verification,
               transaction.productID == ProAccessPolicy.productID,
               transaction.revocationDate == nil {
                hasPurchase = true
                break
            }
        }

        if hasPurchase {
            source = .purchase
            UserDefaults.standard.set(source.rawValue, forKey: sourceKey)
        } else if source == .purchase {
            source = .free
            UserDefaults.standard.set(source.rawValue, forKey: sourceKey)
        }
    }

    private func handleTransactionVerification(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification,
              transaction.productID == ProAccessPolicy.productID else { return }

        await transaction.finish()
        await refreshEntitlements()
    }
}

enum LegacyProMigration {
    static func shouldUnlock(hasExistingUserData: Bool) -> Bool {
        hasExistingUserData
    }
}
