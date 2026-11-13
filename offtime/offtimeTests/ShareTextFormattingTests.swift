import XCTest
@testable import offtime

@MainActor
final class ShareTextFormattingTests: XCTestCase {
    func testClockCopyTextIncludesWeekday() {
        let viewModel = ClockListViewModel()
        viewModel.currentDate = ISO8601DateFormatter().date(
            from: "2026-09-16T02:00:00Z"
        )!
        viewModel.use24Hour = true

        let city = CityModel(
            cityName: "上海",
            cityEn: "Shanghai",
            timezoneId: "Asia/Shanghai"
        )

        let text = viewModel.copyTimeText(city: city)

        XCTAssertTrue(text.contains("2026/09/16 周三"))
        XCTAssertTrue(text.contains("10:00"))
    }

    func testConverterShareTextIncludesSourceAndTargetWeekdays() throws {
        let sourceDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-09-16T02:00:00Z")
        )
        let result = ConvertedTimeResult(
            id: UUID(),
            cityName: "伦敦",
            cityEn: "London",
            countryFlag: "🇬🇧",
            countryName: "United Kingdom",
            utcText: "UTC+1",
            dstText: nil,
            isDaytime: true,
            dateText: "2026/09/16",
            weekdayText: "周三",
            timeText: "03:00",
            differenceText: "-7h",
            crossDayText: nil
        )

        let text = ConverterShareTextBuilder.make(
            sourceName: "Shanghai",
            sourceDate: sourceDate,
            sourceTime: "10:00",
            sourceTimezone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai")),
            results: [result]
        )

        XCTAssertTrue(text.contains("Shanghai 2026/09/16 周三 10:00"))
        let targetName = CityDisplay.primaryName(
            cityName: result.cityName,
            cityEn: result.cityEn
        )
        XCTAssertTrue(text.contains("\(targetName) 2026/09/16 周三 03:00"))
    }
}
