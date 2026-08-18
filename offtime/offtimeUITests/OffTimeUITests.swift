import XCTest

final class OffTimeUITests: XCTestCase {
    func testCompletesOnboardingAndShowsMainTabs() {
        let app = XCUIApplication()
        app.launch()

        if app.buttons["onboarding.start"].exists {
            app.buttons["onboarding.start"].tap()
        }

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 4)
    }
}
