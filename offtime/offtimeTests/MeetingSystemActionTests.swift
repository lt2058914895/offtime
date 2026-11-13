import XCTest
@testable import offtime

final class MeetingSystemActionTests: XCTestCase {
    @MainActor
    func testCalendarIntegrationKeyIgnoresParticipantOrder() throws {
        let start = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-11-20T08:00:00Z")
        )
        let shanghai = MeetingCalendarParticipant(
            cityName: "上海",
            cityEn: "Shanghai",
            timezoneId: "Asia/Shanghai"
        )
        let london = MeetingCalendarParticipant(
            cityName: "伦敦",
            cityEn: "London",
            timezoneId: "Europe/London"
        )

        let first = MeetingCalendarEvent(
            uid: "first",
            startDate: start,
            durationMinutes: 60,
            localTimezoneId: "Asia/Shanghai",
            participants: [shanghai, london]
        )
        let reordered = MeetingCalendarEvent(
            uid: "second",
            startDate: start,
            durationMinutes: 60,
            localTimezoneId: "Asia/Shanghai",
            participants: [london, shanghai]
        )

        XCTAssertEqual(
            MeetingCalendarService.integrationKey(for: first),
            MeetingCalendarService.integrationKey(for: reordered)
        )
    }

    @MainActor
    func testCalendarDeepLinkUsesReferenceDateTimestamp() throws {
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-11-20T01:00:00Z")
        )
        let url = try XCTUnwrap(
            MeetingCalendarService.calendarDeepLink(for: date)
        )

        XCTAssertEqual(
            url.absoluteString,
            "calshow:\(Int(date.timeIntervalSinceReferenceDate.rounded()))"
        )
        XCTAssertNotEqual(
            url.absoluteString,
            "calshow:\(Int(date.timeIntervalSince1970.rounded()))"
        )
    }
}
