import XCTest
@testable import offtime

final class ProAccessPolicyTests: XCTestCase {
    func testLegacyUsersWithExistingDataAreUnlocked() {
        XCTAssertTrue(LegacyProMigration.shouldUnlock(hasExistingUserData: true))
        XCTAssertFalse(LegacyProMigration.shouldUnlock(hasExistingUserData: false))
    }
}
