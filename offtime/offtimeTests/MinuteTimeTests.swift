import SwiftData
import XCTest
@testable import offtime

final class MinuteTimeTests: XCTestCase {
    func testStepAlignmentOnlyAcceptsThirtyMinuteBoundaries() {
        XCTAssertTrue(MinuteTime.isTimeOfDayAlignedToStep(9 * 60))
        XCTAssertTrue(MinuteTime.isTimeOfDayAlignedToStep(9 * 60 + 30))
        XCTAssertFalse(MinuteTime.isTimeOfDayAlignedToStep(9 * 60 + 15))
        XCTAssertFalse(MinuteTime.isTimeOfDayAlignedToStep(MinuteTime.minutesPerDay))
        XCTAssertTrue(MinuteTime.isValidWorkHours(startMinutes: 9 * 60 + 30, endMinutes: 24 * 60))
        XCTAssertFalse(MinuteTime.isValidWorkHours(startMinutes: 9 * 60 + 15, endMinutes: 18 * 60))
    }

    func testSanitizedWorkHoursClampAndSnapToThirtyMinutes() {
        let hours = MinuteTime.sanitizedWorkHours(
            startMinutes: 9 * 60 + 15,
            endMinutes: 18 * 60 + 20
        )
        XCTAssertEqual(hours.start, 9 * 60)
        XCTAssertEqual(hours.end, 18 * 60 + 30)
    }

    @MainActor
    func testLegacyCityModelFallsBackToHourFieldsAndMigratesToMinutes() throws {
        let city = CityModel(
            cityName: "上海",
            cityEn: "Shanghai",
            timezoneId: "Asia/Shanghai",
            workStartHour: 8,
            workEndHour: 17,
            localWorkStart: 10,
            localWorkEnd: 19
        )
        city.workStartMinutes = nil
        city.workEndMinutes = nil
        city.localWorkStartMinutes = nil
        city.localWorkEndMinutes = nil

        XCTAssertEqual(city.workHours, WorkHours(startMinutes: 8 * 60, endMinutes: 17 * 60))
        XCTAssertEqual(city.localWorkHours, WorkHours(startMinutes: 10 * 60, endMinutes: 19 * 60))

        XCTAssertTrue(city.migrateLegacyWorkHoursIfNeeded())
        XCTAssertEqual(city.workStartMinutes, 8 * 60)
        XCTAssertEqual(city.workEndMinutes, 17 * 60)
        XCTAssertEqual(city.localWorkStartMinutes, 10 * 60)
        XCTAssertEqual(city.localWorkEndMinutes, 19 * 60)
        XCTAssertFalse(city.migrateLegacyWorkHoursIfNeeded())
    }

    @MainActor
    func testCityModelStoresHalfHourWorkHoursAndKeepsLegacyHoursReadable() {
        let city = CityModel(
            cityName: "东京",
            cityEn: "Tokyo",
            timezoneId: "Asia/Tokyo",
            workStartMinutes: 9 * 60 + 30,
            workEndMinutes: 17 * 60 + 30
        )

        XCTAssertEqual(city.workHours, WorkHours(startMinutes: 9 * 60 + 30, endMinutes: 17 * 60 + 30))
        XCTAssertEqual(city.workStartHour, 9)
        XCTAssertEqual(city.workEndHour, 17)
    }

    @MainActor
    func testCityDetailContactableSlotsUseThirtyMinuteGrid() throws {
        let city = CityModel(
            cityName: "UTC",
            cityEn: "UTC",
            timezoneId: "Etc/GMT",
            workStartMinutes: 9 * 60 + 30,
            workEndMinutes: 10 * 60 + 30,
            localWorkStartMinutes: 9 * 60 + 30,
            localWorkEndMinutes: 10 * 60 + 30
        )
        let viewModel = CityDetailViewModel(city: city)
        viewModel.localTimezoneId = "Etc/GMT"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Etc/GMT"))
        viewModel.currentDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 1,
                    day: 15,
                    hour: 8
                )
            )
        )

        XCTAssertEqual(
            viewModel.contactableSlots.map(\.localMinuteOfDay),
            [9 * 60 + 30, 10 * 60]
        )
        XCTAssertEqual(
            viewModel.contactableSlots.map(\.targetMinuteOfDay),
            [9 * 60 + 30, 10 * 60]
        )
    }

    func testWallClockSlotsHandleSpringForwardWithoutDuplicates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
        )

        let slotDates = stride(from: 0, to: MinuteTime.minutesPerDay, by: MinuteTime.stepMinutes)
            .compactMap { MinuteTime.date(on: day, minuteOfDay: $0, calendar: calendar) }

        XCTAssertEqual(slotDates.count, MinuteTime.slotCount - 2)
        XCTAssertEqual(Set(slotDates).count, slotDates.count)
        XCTAssertNil(MinuteTime.date(on: day, minuteOfDay: 2 * 60, calendar: calendar))
        XCTAssertNil(MinuteTime.date(on: day, minuteOfDay: 2 * 60 + 30, calendar: calendar))
    }

    func testWallClockSlotsHandleFallBackWithoutDuplicates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))
        )

        let slotDates = stride(from: 0, to: MinuteTime.minutesPerDay, by: MinuteTime.stepMinutes)
            .compactMap { MinuteTime.date(on: day, minuteOfDay: $0, calendar: calendar) }

        XCTAssertEqual(slotDates.count, MinuteTime.slotCount)
        XCTAssertEqual(Set(slotDates).count, slotDates.count)
    }

    @MainActor
    func testCityDetailContactableSlotsRemainUniqueAcrossDST() throws {
        let city = CityModel(
            cityName: "New York",
            cityEn: "New York",
            timezoneId: "America/New_York",
            workStartMinutes: 0,
            workEndMinutes: MinuteTime.minutesPerDay,
            localWorkStartMinutes: 0,
            localWorkEndMinutes: MinuteTime.minutesPerDay
        )
        let viewModel = CityDetailViewModel(city: city)
        viewModel.localTimezoneId = "America/New_York"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let springForward = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
        )
        let fallBack = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))
        )

        viewModel.currentDate = springForward
        let springSlots = viewModel.contactableSlots
        XCTAssertEqual(springSlots.count, MinuteTime.slotCount - 2)
        XCTAssertEqual(Set(springSlots.map(\.localMinuteOfDay)).count, springSlots.count)

        viewModel.currentDate = fallBack
        let fallSlots = viewModel.contactableSlots
        XCTAssertEqual(fallSlots.count, MinuteTime.slotCount)
        XCTAssertEqual(Set(fallSlots.map(\.localMinuteOfDay)).count, fallSlots.count)
        XCTAssertEqual(Set(fallSlots.map(\.date)).count, fallSlots.count)
    }
}
