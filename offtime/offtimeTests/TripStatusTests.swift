import XCTest
@testable import offtime

final class TripStatusTests: XCTestCase {
    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        timezoneId: String = "Asia/Shanghai"
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

    private func city(id: String, name: String, timezoneId: String) -> CitySuggestion {
        CitySuggestion(
            id: id,
            cityName: name,
            cityEn: name,
            timezoneId: timezoneId,
            continent: "asia"
        )
    }

    private func trip(start: Date, end: Date, timezoneId: String = "Asia/Shanghai") -> TripModel {
        let leg = TravelLeg(
            origin: city(id: "1", name: "A", timezoneId: timezoneId),
            destination: city(id: "2", name: "B", timezoneId: timezoneId),
            departureDate: start,
            arrivalDate: start.addingTimeInterval(60 * 60)
        )
        return TripModel(legs: [leg], tripEndDate: end)
    }

    // MARK: - 状态推导

    func testBeforeDepartureIsUpcoming() throws {
        let departure = try date(year: 2026, month: 8, day: 25, hour: 9)
        let now = try date(year: 2026, month: 8, day: 25, hour: 8)
        XCTAssertEqual(
            TripStatus.status(
                at: now,
                firstDeparture: departure,
                tripEndDate: try date(year: 2026, month: 8, day: 28),
                timezoneId: "Asia/Shanghai"
            ),
            .upcoming
        )
    }

    func testDuringTripIsOngoing() throws {
        let departure = try date(year: 2026, month: 8, day: 25, hour: 9)
        let now = try date(year: 2026, month: 8, day: 26, hour: 10)
        XCTAssertEqual(
            TripStatus.status(
                at: now,
                firstDeparture: departure,
                tripEndDate: try date(year: 2026, month: 8, day: 28),
                timezoneId: "Asia/Shanghai"
            ),
            .ongoing
        )
    }

    func testOnTripEndDayIsOngoing() throws {
        let departure = try date(year: 2026, month: 8, day: 25, hour: 9)
        let now = try date(year: 2026, month: 8, day: 28, hour: 23, minute: 59)
        XCTAssertEqual(
            TripStatus.status(
                at: now,
                firstDeparture: departure,
                tripEndDate: try date(year: 2026, month: 8, day: 28),
                timezoneId: "Asia/Shanghai"
            ),
            .ongoing
        )
    }

    func testAfterTripEndDayIsFinished() throws {
        let departure = try date(year: 2026, month: 8, day: 25, hour: 9)
        let now = try date(year: 2026, month: 8, day: 29, hour: 0, minute: 1)
        XCTAssertEqual(
            TripStatus.status(
                at: now,
                firstDeparture: departure,
                tripEndDate: try date(year: 2026, month: 8, day: 28),
                timezoneId: "Asia/Shanghai"
            ),
            .finished
        )
    }

    func testMissingDepartureIsUpcoming() throws {
        XCTAssertEqual(
            TripStatus.status(
                at: Date(),
                firstDeparture: nil,
                tripEndDate: Date(),
                timezoneId: "Asia/Shanghai"
            ),
            .upcoming
        )
    }

    // MARK: - 时间区间重叠

    func testOverlappingTripsDetected() throws {
        let tripA = trip(
            start: try date(year: 2026, month: 8, day: 1),
            end: try date(year: 2026, month: 8, day: 10)
        )
        let tripB = trip(
            start: try date(year: 2026, month: 8, day: 5),
            end: try date(year: 2026, month: 8, day: 15)
        )
        XCTAssertTrue(tripA.overlaps(tripB))
        XCTAssertTrue(tripB.overlaps(tripA))
    }

    func testAdjacentTripsDoNotOverlap() throws {
        let tripA = trip(
            start: try date(year: 2026, month: 8, day: 1),
            end: try date(year: 2026, month: 8, day: 10)
        )
        let tripB = trip(
            start: try date(year: 2026, month: 8, day: 11),
            end: try date(year: 2026, month: 8, day: 15)
        )
        XCTAssertFalse(tripA.overlaps(tripB))
        XCTAssertFalse(tripB.overlaps(tripA))
    }

    func testSameTimeTripsOverlap() throws {
        let tripA = trip(
            start: try date(year: 2026, month: 8, day: 1),
            end: try date(year: 2026, month: 8, day: 10)
        )
        let tripB = trip(
            start: try date(year: 2026, month: 8, day: 1),
            end: try date(year: 2026, month: 8, day: 10)
        )
        XCTAssertTrue(tripA.overlaps(tripB))
    }
}
