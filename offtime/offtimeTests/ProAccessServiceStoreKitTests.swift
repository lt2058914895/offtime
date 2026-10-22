import XCTest
import StoreKit
import StoreKitTest
@testable import offtime

@MainActor
final class ProAccessServiceStoreKitTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var service: ProAccessService!

    override func setUpWithError() throws {
        try super.setUpWithError()

        session = try XCTUnwrap(SKTestSession(configurationFileNamed: "Products"))
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        suiteName = "ProAccessServiceStoreKitTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        service = ProAccessService(defaults: defaults)
    }

    override func tearDownWithError() throws {
        session?.clearTransactions()
        if let suiteName = suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        service = nil
        defaults = nil
        suiteName = nil
        session = nil
        try super.tearDownWithError()
    }

    func testProductLoadsFromConfiguration() async throws {
        XCTAssertNil(service.priceText)

        await service.load()

        let product = try XCTUnwrap(service.product)
        XCTAssertEqual(product.id, ProAccessPolicy.productID)
        XCTAssertEqual(product.type, .nonConsumable)
        XCTAssertEqual(try XCTUnwrap(service.priceText), product.displayPrice)
        XCTAssertFalse(service.isUnlocked)
        XCTAssertFalse(service.isLoadingProducts)
    }

    func testPurchaseUnlocksAndRestoresFromCurrentEntitlements() async throws {
        let transaction = try await session.buyProduct(identifier: ProAccessPolicy.productID)
        await transaction.finish()

        await service.refreshEntitlements()

        XCTAssertTrue(service.isUnlocked)
        XCTAssertEqual(service.source.rawValue, ProAccessSource.purchase.rawValue)

        let freshSuiteName = "ProAccessServiceStoreKitTests.\(UUID().uuidString)"
        let freshDefaults = try XCTUnwrap(UserDefaults(suiteName: freshSuiteName))
        freshDefaults.removePersistentDomain(forName: freshSuiteName)
        defer { freshDefaults.removePersistentDomain(forName: freshSuiteName) }

        let reinstalledService = ProAccessService(defaults: freshDefaults)
        await reinstalledService.refreshEntitlements()
        XCTAssertTrue(reinstalledService.isUnlocked)
    }

    func testRefundRemovesEntitlement() async throws {
        let transaction = try await session.buyProduct(identifier: ProAccessPolicy.productID)
        await transaction.finish()
        await service.refreshEntitlements()
        XCTAssertTrue(service.isUnlocked)

        let testTransaction = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProAccessPolicy.productID }
        )
        try session.refundTransaction(identifier: testTransaction.identifier)

        await service.refreshEntitlements()
        XCTAssertFalse(service.isUnlocked)
    }

    func testAskToBuyPurchaseStaysPendingUntilApproved() async throws {
        await service.load()
        XCTAssertNotNil(service.product)

        session.askToBuyEnabled = true
        await service.purchase()

        XCTAssertFalse(service.isUnlocked)
        XCTAssertNotNil(service.statusMessage)

        let pendingTransaction = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == ProAccessPolicy.productID }
        )
        XCTAssertTrue(pendingTransaction.pendingAskToBuyConfirmation)

        try session.approveAskToBuyTransaction(identifier: pendingTransaction.identifier)
        await service.refreshEntitlements()
        XCTAssertTrue(service.isUnlocked)
    }

    func testLegacyMigrationUnlocksExistingUsersOnlyOnce() {
        service.migrateLegacyIfNeeded(hasExistingUserData: true)
        XCTAssertTrue(service.isLegacyUnlocked)
        XCTAssertTrue(service.isUnlocked)

        service.migrateLegacyIfNeeded(hasExistingUserData: false)
        XCTAssertTrue(service.isLegacyUnlocked)
    }

    func testFreshInstallDoesNotReceiveLegacyUnlock() {
        service.migrateLegacyIfNeeded(hasExistingUserData: false)
        XCTAssertFalse(service.isUnlocked)
    }
}
