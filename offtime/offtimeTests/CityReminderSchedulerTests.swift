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
                weekdaysOnly: true
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
                weekdaysOnly: true
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
                weekdaysOnly: false
            )
        )

        XCTAssertEqual(
            occurrence,
            try date(year: 2026, month: 8, day: 23, hour: 9, minute: 0)
        )
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
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        let timezone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
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
