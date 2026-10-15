import XCTest
@testable import offtime

final class ProAccessPolicyTests: XCTestCase {
    func testSystemThemeIsFreeAndExplicitThemesRequirePurchase() {
        XCTAssertTrue(ProAccessPolicy.isThemeUnlocked(.system, isUnlocked: false))
        XCTAssertFalse(ProAccessPolicy.isThemeUnlocked(.light, isUnlocked: false))
        XCTAssertFalse(ProAccessPolicy.isThemeUnlocked(.dark, isUnlocked: false))
        XCTAssertTrue(ProAccessPolicy.isThemeUnlocked(.light, isUnlocked: true))
    }

    func testLegacyUsersWithExistingDataAreUnlocked() {
        XCTAssertTrue(LegacyProMigration.shouldUnlock(hasExistingUserData: true))
        XCTAssertFalse(LegacyProMigration.shouldUnlock(hasExistingUserData: false))
    }
}
