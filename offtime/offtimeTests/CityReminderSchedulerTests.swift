import XCTest
@testable import offtime

final class CityReminderSchedulerTests: XCTestCase {
    func testNextOccurrenceLaterToday() throws {
        let after = try date(year: 2026, month: 8, day: 21, hour: 8, minute: 0)
        let occurrence = try XCTUnwrap(
            CityReminderScheduler.nextOccurrence(
                after: after,
                timezoneId: "America/Los_Angeles",
                hour: 9,
                minute: 0,
                targetTimezoneId: "America/Los_Angeles",
                weekdayPolicy: .bothCities
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(year: 2026, month: 8, day: 21, hour: 9, minute: 0)
        )
    }

    func testWeekdayOnlyReminderSkipsWeekend() throws {
        let after = try date(year: 2026, month: 8, day: 21, hour: 10, minute: 0)
        let occurrence = try XCTUnwrap(
            CityReminderScheduler.nextOccurrence(
                after: after,
                timezoneId: "America/Los_Angeles",
                hour: 9,
                minute: 0,
                targetTimezoneId: "America/Los_Angeles",
                weekdayPolicy: .bothCities
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(year: 2026, month: 8, day: 24, hour: 9, minute: 0)
        )
    }

    func testDailyReminderCanOccurOnWeekend() throws {
        let after = try date(year: 2026, month: 8, day: 22, hour: 10, minute: 0)
        let occurrence = try XCTUnwrap(
            CityReminderScheduler.nextOccurrence(
                after: after,
                timezoneId: "America/Los_Angeles",
                hour: 9,
                minute: 0,
                targetTimezoneId: "America/Los_Angeles",
                weekdayPolicy: .everyDay
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(year: 2026, month: 8, day: 23, hour: 9, minute: 0)
        )
    }

    func testWeekdayOnlySkipsWhenTargetCityIsWeekend() throws {
        let after = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let occurrence = try XCTUnwrap(
            CityReminderScheduler.nextOccurrence(
                after: after,
                timezoneId: "Asia/Shanghai",
                hour: 9,
                minute: 0,
                targetTimezoneId: "America/Los_Angeles",
                weekdayPolicy: .bothCities
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(
                timezoneId: "Asia/Shanghai",
                year: 2026,
                month: 8,
                day: 25,
                hour: 9,
                minute: 0
            )
        )
    }

    func testCurrentCityPolicyAllowsTargetCityWeekend() throws {
        let after = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let occurrence = try XCTUnwrap(
            CityReminderScheduler.nextOccurrence(
                after: after,
                timezoneId: "Asia/Shanghai",
                hour: 9,
                minute: 0,
                targetTimezoneId: "America/Los_Angeles",
                weekdayPolicy: .currentCity
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(
                timezoneId: "Asia/Shanghai",
                year: 2026,
                month: 8,
                day: 24,
                hour: 9,
                minute: 0
            )
        )
    }

    func testTargetCityPolicyAllowsLocalWeekend() throws {
        let after = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 28,
            hour: 10,
            minute: 0
        )
        let occurrence = try XCTUnwrap(
            CityReminderScheduler.nextOccurrence(
                after: after,
                timezoneId: "Asia/Shanghai",
                hour: 9,
                minute: 0,
                targetTimezoneId: "America/Los_Angeles",
                weekdayPolicy: .targetCity
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(
                timezoneId: "Asia/Shanghai",
                year: 2026,
                month: 8,
                day: 29,
                hour: 9,
                minute: 0
            )
        )
    }

    func testIsWeekendIdentifiesEachCity() throws {
        let targetWeekend = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 24,
            hour: 9,
            minute: 0
        )
        XCTAssertEqual(
            CityReminderScheduler.isWeekend(at: targetWeekend, timezoneId: "Asia/Shanghai"),
            false
        )
        XCTAssertEqual(
            CityReminderScheduler.isWeekend(at: targetWeekend, timezoneId: "America/Los_Angeles"),
            true
        )

        let currentWeekend = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 22,
            hour: 9,
            minute: 0
        )
        XCTAssertEqual(
            CityReminderScheduler.isWeekend(at: currentWeekend, timezoneId: "Asia/Shanghai"),
            true
        )
    }

    func testRepeatWeekdaysKeepsOnlyDaysThatAreWorkdaysInBothCities() throws {
        let reference = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )

        let weekdays = CityReminderScheduler.repeatWeekdays(
            after: reference,
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            targetTimezoneId: "America/Los_Angeles",
            weekdayPolicy: .bothCities
        )

        XCTAssertEqual(weekdays, [3, 4, 5, 6])
    }

    func testRepeatWeekdaysForCurrentCityPolicy() throws {
        let reference = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )

        let weekdays = CityReminderScheduler.repeatWeekdays(
            after: reference,
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            targetTimezoneId: "America/Los_Angeles",
            weekdayPolicy: .currentCity
        )

        XCTAssertEqual(weekdays, [2, 3, 4, 5, 6])
    }

    func testRepeatWeekdaysForTargetCityPolicyCanIncludeLocalWeekend() throws {
        let reference = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )

        let weekdays = CityReminderScheduler.repeatWeekdays(
            after: reference,
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            targetTimezoneId: "America/Los_Angeles",
            weekdayPolicy: .targetCity
        )

        XCTAssertEqual(weekdays, [3, 4, 5, 6, 7])
    }

    func testTriggerComponentsUseTargetTimezoneAndWeekday() throws {
        let components = try XCTUnwrap(
            CityReminderScheduler.triggerComponents(
                hour: 9,
                minute: 30,
                timezoneId: "America/New_York",
                weekday: 2
            )
        )
        let timezone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.weekday, 2)
        XCTAssertEqual(components.timeZone, timezone)
    }

    private func date(
        timezoneId: String = "America/Los_Angeles",
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        let timezone = try XCTUnwrap(TimeZone(identifier: timezoneId))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
