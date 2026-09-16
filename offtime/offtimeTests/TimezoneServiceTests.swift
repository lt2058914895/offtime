import XCTest
@testable import offtime

@MainActor
final class TimezoneServiceTests: XCTestCase {
    private let service = TimezoneService.shared

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timezoneId: String
    ) throws -> Date {
        let timezone = try XCTUnwrap(TimeZone(identifier: timezoneId))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    func testCrossDayLabelFollowsTargetCalendarDay() throws {
        let source = try date(
            year: 2026,
            month: 8,
            day: 18,
            hour: 23,
            minute: 0,
            timezoneId: "Etc/GMT+9"
        )

        let forward = service.getTimeDifferenceBetween(
            sourceTimezoneId: "Etc/GMT+9",
            targetTimezoneId: "Etc/GMT-14",
            date: source
        )
        XCTAssertEqual(forward.offset, "+23h")
        XCTAssertNotNil(forward.crossDay)

        let reverseSource = try date(
            year: 2026,
            month: 8,
            day: 19,
            hour: 0,
            minute: 0,
            timezoneId: "Etc/GMT-14"
        )
        let reverse = service.getTimeDifferenceBetween(
            sourceTimezoneId: "Etc/GMT-14",
            targetTimezoneId: "Etc/GMT+9",
            date: reverseSource
        )
        XCTAssertEqual(reverse.offset, "-23h")
        XCTAssertNotNil(reverse.crossDay)
    }

    func testTimeDifferencePreservesThirtyMinutePrecision() throws {
        let source = try date(
            year: 2026,
            month: 1,
            day: 15,
            hour: 12,
            minute: 0,
            timezoneId: "Etc/GMT"
        )

        let difference = service.getTimeDifferenceBetween(
            sourceTimezoneId: "Etc/GMT",
            targetTimezoneId: "Pacific/Chatham",
            date: source
        )

        XCTAssertEqual(difference.offset, "+13h45m")
    }

    func testWorkingHoursOverlapCountsSharedHours() throws {
        let date = try self.date(
            year: 2026,
            month: 1,
            day: 15,
            hour: 10,
            minute: 0,
            timezoneId: "Etc/GMT"
        )

        let overlap = service.getWorkingHoursOverlap(
            timezoneId: "Etc/GMT-2",
            date: date,
            localTimezoneId: "Etc/GMT",
            localWorkStart: 9,
            localWorkEnd: 18,
            targetWorkStart: 8,
            targetWorkEnd: 17
        )

        XCTAssertEqual(overlap.hourlyOverlap.filter { $0 }.count, 8)
        XCTAssertTrue(overlap.isCurrentlyOverlapping)
    }

    /// 回归：小组件底部日期行由「星期 + 月日」拼成，若月日文本自带星期
    /// 就会出现「周三 09/16周三」这种重复展示（旧版 MMEd 模板的问题）。
    func testMonthDayOnlyIsFreeOfWeekdayForWidgetDateLine() throws {
        let instant = try date(
            year: 2026,
            month: 9,
            day: 16,
            hour: 10,
            minute: 0,
            timezoneId: "Asia/Shanghai"
        )
        let timezoneId = "Asia/Shanghai"

        let weekday = try XCTUnwrap(service.getLocalWeekday(timezoneId: timezoneId, date: instant))
        let monthDay = try XCTUnwrap(service.getMonthDayOnly(timezoneId: timezoneId, date: instant))
        let weekdayInclusiveMonthDay = try XCTUnwrap(service.getMonthDay(timezoneId: timezoneId, date: instant))

        // MMEd（含星期）与 MMMd（不含星期）必须是两种不同文本
        XCTAssertTrue(weekdayInclusiveMonthDay.contains(weekday))
        XCTAssertNotEqual(monthDay, weekdayInclusiveMonthDay, "「月日」文本不能退回带星期的 MMEd 模板")
    }
}
