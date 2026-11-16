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

        // 本地 9–18 点与目标 UTC+2 的 8–17 点（即 UTC 6–15 点）相交 9–15 点，共 6 小时。
        XCTAssertEqual(overlap.hourlyOverlap.filter { $0 }.count, 6)
        XCTAssertTrue(overlap.isCurrentlyOverlapping)
    }

    func testWorkingHoursOverlapUsesHalfHourGranularity() throws {
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
            localWorkStartMinutes: 9 * 60 + 30,
            localWorkEndMinutes: 18 * 60,
            targetWorkStartMinutes: 8 * 60,
            targetWorkEndMinutes: 17 * 60
        )

        // 本地 9:30–18:00 与目标城市 8:00–17:00 相交为本地 9:30–15:00。
        XCTAssertEqual(overlap.halfHourlyOverlap.filter { $0 }.count, 11)
        XCTAssertFalse(overlap.halfHourlyOverlap[18])
        XCTAssertTrue(overlap.halfHourlyOverlap[19])
        XCTAssertTrue(overlap.halfHourlyOverlap[29])
        XCTAssertFalse(overlap.halfHourlyOverlap[30])
        XCTAssertTrue(overlap.isCurrentlyOverlapping)
    }

    /// 回归：所有用户可见日期都必须使用带四位年份的斜杠格式，
    /// 且日期与星期分开格式化，避免小组件出现重复星期。
    func testUserVisibleDateUsesSlashFormatWithoutDuplicateWeekday() throws {
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
        let date = try XCTUnwrap(service.getLocalDate(timezoneId: timezoneId, date: instant))
        let dateWithWeekday = try XCTUnwrap(
            service.getLocalDateWithWeekday(timezoneId: timezoneId, date: instant)
        )

        XCTAssertEqual(date, "2026/09/16")
        XCTAssertEqual(weekday, "周三")
        XCTAssertEqual(dateWithWeekday, "2026/09/16 周三")
    }

    func testWeekdayUsesCompactChineseNamesForEveryDay() throws {
        let expected = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

        for (offset, weekdayName) in expected.enumerated() {
            let instant = try date(
                year: 2026,
                month: 11,
                day: 9 + offset,
                hour: 10,
                minute: 0,
                timezoneId: "Asia/Shanghai"
            )
            XCTAssertEqual(
                service.getLocalWeekday(timezoneId: "Asia/Shanghai", date: instant),
                weekdayName
            )
        }
    }

    func testCrossDayTimeRangeKeepsStartDateAndMarksNextDay() throws {
        let timezone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let start = try date(
            year: 2026,
            month: 11,
            day: 16,
            hour: 23,
            minute: 30,
            timezoneId: "Asia/Shanghai"
        )
        let end = start.addingTimeInterval(60 * 60)

        XCTAssertEqual(
            DateDisplayFormat.dateWithWeekday(start, timezone: timezone),
            "2026/11/16 周一"
        )
        XCTAssertEqual(
            DateDisplayFormat.timeRange(
                start: start,
                end: end,
                timezone: timezone,
                use24Hour: true,
                locale: Locale(identifier: "zh_CN")
            ),
            "23:30–次日 00:30"
        )
        XCTAssertEqual(
            DateDisplayFormat.timeRange(
                start: start,
                end: end,
                timezone: timezone,
                use24Hour: false,
                locale: Locale(identifier: "en_US")
            ),
            "11:30 PM–next day 12:30 AM"
        )
    }
}
