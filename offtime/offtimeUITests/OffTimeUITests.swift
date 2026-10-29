import XCTest

final class OffTimeUITests: XCTestCase {
    func testShowsMainTabs() {
        let app = XCUIApplication()
        app.launchArguments += ["-onboarding_completed", "YES"]
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
    }
}
