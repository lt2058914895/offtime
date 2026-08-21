import XCTest
@testable import offtime

final class TravelPlannerServiceTests: XCTestCase {
    private let service = TravelPlannerService.shared

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

    private func city(id: String, name: String, timezoneId: String, continent: String) -> CitySuggestion {
        CitySuggestion(
            id: id,
            cityName: name,
            cityEn: name,
            timezoneId: timezoneId,
            continent: continent
        )
    }

    func testShanghaiToLosAngelesPlanUsesDSTAndCreatesTimeline() throws {
        let shanghai = city(
            id: "Asia/Shanghai",
            name: "Shanghai",
            timezoneId: "Asia/Shanghai",
            continent: "asia"
        )
        let losAngeles = city(
            id: "America/Los_Angeles",
            name: "Los Angeles",
            timezoneId: "America/Los_Angeles",
            continent: "america"
        )
        let departure = try date(
            year: 2026,
            month: 8,
            day: 19,
            hour: 11,
            minute: 0,
            timezoneId: "Asia/Shanghai"
        )
        let arrival = try date(
            year: 2026,
            month: 8,
            day: 19,
            hour: 8,
            minute: 0,
            timezoneId: "America/Los_Angeles"
        )

        let plan = try service.makePlan(
            origin: shanghai,
            destination: losAngeles,
            departureDate: departure,
            arrivalDate: arrival,
            tripDays: 3
        )

        XCTAssertEqual(plan.offsetMinutes, -900)
        XCTAssertEqual(plan.offsetText, "-15h")
        XCTAssertEqual(plan.direction, .behind)
        XCTAssertEqual(plan.adjustmentLevel, .large)
        XCTAssertEqual(plan.flightDuration / 3600, 12, accuracy: 0.01)
        XCTAssertEqual(plan.flightDurationText, "12h")

        let kinds = plan.timeline.map(\.kind)
        XCTAssertTrue(kinds.contains(.arrival))
        XCTAssertTrue(kinds.contains(.daylight))
        XCTAssertTrue(kinds.contains(.sleep))
        XCTAssertEqual(plan.timeline.filter { $0.dayIndex == 3 }.count, 3)
    }

    func testInvalidArrivalThrows() throws {
        let departure = try date(
            year: 2026,
            month: 8,
            day: 19,
            hour: 11,
            minute: 0,
            timezoneId: "Asia/Shanghai"
        )

        XCTAssertThrowsError(
            try service.makePlan(
                origin: city(id: "1", name: "Shanghai", timezoneId: "Asia/Shanghai", continent: "asia"),
                destination: city(id: "2", name: "Los Angeles", timezoneId: "America/Los_Angeles", continent: "america"),
                departureDate: departure,
                arrivalDate: departure,
                tripDays: 3
            )
        ) { error in
            XCTAssertEqual(error as? TravelPlanError, .invalidArrival(index: nil))
        }
    }

    func testMultiCityItineraryUsesEndDateAndStopDates() throws {
        let shanghai = city(id: "Asia/Shanghai", name: "Shanghai", timezoneId: "Asia/Shanghai", continent: "asia")
        let losAngeles = city(id: "America/Los_Angeles", name: "Los Angeles", timezoneId: "America/Los_Angeles", continent: "america")
        let newYork = city(id: "America/New_York", name: "New York", timezoneId: "America/New_York", continent: "america")
        let departure = try date(year: 2026, month: 8, day: 19, hour: 11, minute: 0, timezoneId: "Asia/Shanghai")
        let losAngelesArrival = try date(year: 2026, month: 8, day: 19, hour: 8, minute: 0, timezoneId: "America/Los_Angeles")
        let nextDeparture = try date(year: 2026, month: 8, day: 22, hour: 9, minute: 0, timezoneId: "America/Los_Angeles")
        let newYorkArrival = try date(year: 2026, month: 8, day: 22, hour: 18, minute: 0, timezoneId: "America/New_York")
        let tripEndDate = try date(year: 2026, month: 8, day: 29, hour: 12, minute: 0, timezoneId: "America/New_York")

        let itinerary = try service.makeItinerary(
            legs: [
                TravelLeg(origin: shanghai, destination: losAngeles, departureDate: departure, arrivalDate: losAngelesArrival),
                TravelLeg(origin: losAngeles, destination: newYork, departureDate: nextDeparture, arrivalDate: newYorkArrival)
            ],
            tripEndDate: tripEndDate
        )

        XCTAssertEqual(itinerary.routeNames, ["Shanghai", "Los Angeles", "New York"])
        XCTAssertEqual(itinerary.plans.count, 2)
        XCTAssertEqual(itinerary.plans[0].tripDays, 4)
        XCTAssertEqual(itinerary.plans[1].tripDays, 8)
    }

    func testMultiCityItineraryRejectsDiscontinuousRoute() throws {
        let shanghai = city(id: "Asia/Shanghai", name: "Shanghai", timezoneId: "Asia/Shanghai", continent: "asia")
        let losAngeles = city(id: "America/Los_Angeles", name: "Los Angeles", timezoneId: "America/Los_Angeles", continent: "america")
        let sanFrancisco = city(id: "America/Los_Angeles_SF", name: "San Francisco", timezoneId: "America/Los_Angeles", continent: "america")
        let newYork = city(id: "America/New_York", name: "New York", timezoneId: "America/New_York", continent: "america")
        let departure = try date(year: 2026, month: 8, day: 19, hour: 11, minute: 0, timezoneId: "Asia/Shanghai")
        let arrival = try date(year: 2026, month: 8, day: 19, hour: 8, minute: 0, timezoneId: "America/Los_Angeles")
        let nextDeparture = try date(year: 2026, month: 8, day: 22, hour: 9, minute: 0, timezoneId: "America/Los_Angeles")
        let nextArrival = try date(year: 2026, month: 8, day: 22, hour: 18, minute: 0, timezoneId: "America/New_York")

        XCTAssertThrowsError(
            try service.makeItinerary(
                legs: [
                    TravelLeg(origin: shanghai, destination: losAngeles, departureDate: departure, arrivalDate: arrival),
                    TravelLeg(origin: sanFrancisco, destination: newYork, departureDate: nextDeparture, arrivalDate: nextArrival)
                ],
                tripEndDate: nextArrival.addingTimeInterval(24 * 60 * 60)
            )
        ) { error in
            XCTAssertEqual(error as? TravelPlanError, .discontinuousRoute(index: 1))
        }
    }

    func testPersonalizedScheduleTimesCreateTimelineEvents() throws {
        let shanghai = city(id: "Asia/Shanghai", name: "Shanghai", timezoneId: "Asia/Shanghai", continent: "asia")
        let losAngeles = city(id: "America/Los_Angeles", name: "Los Angeles", timezoneId: "America/Los_Angeles", continent: "america")
        let departure = try date(year: 2026, month: 8, day: 19, hour: 11, minute: 0, timezoneId: "Asia/Shanghai")
        let arrival = try date(year: 2026, month: 8, day: 19, hour: 8, minute: 0, timezoneId: "America/Los_Angeles")

        let plan = try service.makePlan(
            origin: shanghai,
            destination: losAngeles,
            departureDate: departure,
            arrivalDate: arrival,
            tripDays: 2,
            wakeTime: TravelScheduleTime(hour: 6, minute: 30),
            sleepTime: TravelScheduleTime(hour: 23, minute: 15)
        )

        let timezone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let wake = try XCTUnwrap(plan.timeline.first { $0.kind == .wake && $0.dayIndex == 2 })
        let sleep = try XCTUnwrap(plan.timeline.first { $0.kind == .sleep && $0.dayIndex == 2 })

        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: wake.destinationDate), DateComponents(hour: 6, minute: 30))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: sleep.destinationDate), DateComponents(hour: 23, minute: 15))
    }

    func testDraftStoreSavesAndLoadsLatestDraft() throws {
        let suiteName = "TravelDraftStoreTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = TravelDraftStore(defaults: defaults, storageKey: "test_draft")
        let draft = TravelDraft(
            legs: [
                TravelLeg(
                    origin: city(id: "1", name: "Shanghai", timezoneId: "Asia/Shanghai", continent: "asia"),
                    destination: city(id: "2", name: "Los Angeles", timezoneId: "America/Los_Angeles", continent: "america"),
                    departureDate: Date(timeIntervalSince1970: 1_000),
                    arrivalDate: Date(timeIntervalSince1970: 40_000)
                )
            ],
            tripEndDate: Date(timeIntervalSince1970: 200_000),
            wakeTime: TravelScheduleTime(hour: 6, minute: 30),
            sleepTime: TravelScheduleTime(hour: 23, minute: 15),
            activeLegIndex: 0
        )

        store.save(draft)
        XCTAssertEqual(store.load(), draft)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
