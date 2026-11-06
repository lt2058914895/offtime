import XCTest
@testable import offtime

@MainActor
final class MeetingCalendarExportServiceTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func event(
        uid: String = "meeting-1",
        startDate: Date = ISO8601DateFormatter().date(from: "2026-11-07T07:30:00Z")!,
        durationMinutes: Int = 60,
        localTimezoneId: String = "Asia/Shanghai",
        participants: [MeetingCalendarParticipant] = [
            MeetingCalendarParticipant(
                cityName: "Shanghai",
                cityEn: "Shanghai",
                timezoneId: "Asia/Shanghai"
            ),
            MeetingCalendarParticipant(
                cityName: "London",
                cityEn: "London",
                timezoneId: "Europe/London"
            )
        ]
    ) -> MeetingCalendarEvent {
        MeetingCalendarEvent(
            uid: uid,
            startDate: startDate,
            durationMinutes: durationMinutes,
            localTimezoneId: localTimezoneId,
            participants: participants
        )
    }

    private func unfolded(_ ics: String) -> String {
        ics.replacingOccurrences(of: "\r\n ", with: "")
    }

    func testICSContainsAbsoluteStartAndEndTimes() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(),
            now: date("2026-11-06T00:00:00Z")
        )

        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("\r\nUID:meeting-1@offtime.lt\r\n"))
        XCTAssertTrue(ics.contains("\r\nDTSTAMP:20261106T000000Z\r\n"))
        XCTAssertTrue(ics.contains("\r\nDTSTART:20261107T073000Z\r\n"))
        XCTAssertTrue(ics.contains("\r\nDTEND:20261107T083000Z\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
    }

    func testAllCitiesAreIncludedInSummary() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(participants: [
                MeetingCalendarParticipant(cityName: "Shanghai", cityEn: "Shanghai", timezoneId: "Asia/Shanghai"),
                MeetingCalendarParticipant(cityName: "London", cityEn: "London", timezoneId: "Europe/London"),
                MeetingCalendarParticipant(cityName: "Los Angeles", cityEn: "Los Angeles", timezoneId: "America/Los_Angeles"),
                MeetingCalendarParticipant(cityName: "New York", cityEn: "New York", timezoneId: "America/New_York")
            ])
        )
        let summary = unfolded(ics)
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix("SUMMARY:") } ?? ""

        XCTAssertTrue(summary.contains("Shanghai"))
        XCTAssertTrue(summary.contains("London"))
        XCTAssertTrue(summary.contains("Los Angeles"))
        XCTAssertTrue(summary.contains("New York"))
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("OffTime"))
    }

    func testSavedMeetingUIDRemainsStableAcrossExports() {
        let first = MeetingCalendarExportService.makeICS(event: event(uid: "stable-meeting"))
        let second = MeetingCalendarExportService.makeICS(event: event(uid: "stable-meeting"))

        XCTAssertTrue(first.contains("\r\nUID:stable-meeting@offtime.lt\r\n"))
        XCTAssertTrue(second.contains("\r\nUID:stable-meeting@offtime.lt\r\n"))
    }

    func testTextEscapingFollowsRFC5545() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(participants: [
                MeetingCalendarParticipant(
                    cityName: "A, B; C\\D",
                    cityEn: "A, B; C\\D",
                    timezoneId: "Asia/Shanghai"
                )
            ])
        )

        XCTAssertTrue(unfolded(ics).contains(#"A\, B\; C\\D"#))
    }

    func testNewlinesAreEscapedAsLiteralLineBreaks() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(participants: [
                MeetingCalendarParticipant(
                    cityName: "Shanghai\nLondon",
                    cityEn: "Shanghai\nLondon",
                    timezoneId: "Asia/Shanghai"
                )
            ])
        )

        XCTAssertTrue(unfolded(ics).contains(#"Shanghai\nLondon"#))
    }

    func testDescriptionDoesNotIncludeGeneratedByFooter() {
        let ics = MeetingCalendarExportService.makeICS(event: event())
        let description = unfolded(ics)
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix("DESCRIPTION:") } ?? ""

        XCTAssertFalse(description.localizedCaseInsensitiveContains("OffTime"))
    }

    func testDescriptionListsEveryCityDateAndTime() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(),
            locale: Locale(identifier: "zh_CN")
        )
        let description = unfolded(ics)
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix("DESCRIPTION:") } ?? ""

        XCTAssertTrue(description.contains("Shanghai"))
        XCTAssertTrue(description.contains("London"))
        XCTAssertTrue(description.contains("2026年11月7日 星期六"))
        XCTAssertTrue(description.contains("15:30–16:30"))
        XCTAssertTrue(description.contains("07:30–08:30"))
        XCTAssertFalse(description.contains("UTC+"))
        XCTAssertFalse(description.contains("UTC-"))
        XCTAssertEqual(description.components(separatedBy: "–").count, 3)
    }

    func testDescriptionFollowsLocaleAndTwelveHourClock() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(),
            locale: Locale(identifier: "en_US")
        )
        let description = unfolded(ics)
            .components(separatedBy: "\r\n")
            .first { $0.hasPrefix("DESCRIPTION:") } ?? ""

        XCTAssertTrue(description.contains("Saturday, November 7, 2026"))
        XCTAssertTrue(description.contains("3:30"))
        XCTAssertTrue(description.contains("PM"))
        XCTAssertFalse(description.contains("15:30"))
    }

    func testTimezoneResolverUsesUniqueSavedCityMatch() {
        let savedCities = [
            MeetingCityTimezoneCandidate(
                cityName: "伦敦",
                cityEn: "London",
                timezoneId: "Europe/London"
            )
        ]

        XCTAssertEqual(
            MeetingCityTimezoneResolver.timezoneId(
                cityName: "伦敦",
                cityEn: "London",
                candidates: savedCities
            ),
            "Europe/London"
        )
    }

    func testTimezoneResolverRejectsAmbiguousCatalogMatchWithoutLocalPreference() {
        let catalogCities = [
            MeetingCityTimezoneCandidate(
                cityName: "伦敦",
                cityEn: "London",
                timezoneId: "Europe/London"
            ),
            MeetingCityTimezoneCandidate(
                cityName: "伦敦",
                cityEn: "London",
                timezoneId: "America/Toronto"
            )
        ]

        XCTAssertNil(
            MeetingCityTimezoneResolver.timezoneId(
                cityName: "伦敦",
                cityEn: "London",
                candidates: catalogCities
            )
        )
        XCTAssertEqual(
            MeetingCityTimezoneResolver.timezoneId(
                cityName: "伦敦",
                cityEn: "London",
                candidates: catalogCities,
                preferredTimezoneId: "America/Toronto"
            ),
            "America/Toronto"
        )
    }

    func testPhysicalLinesDoNotExceedSeventyFiveBytes() {
        let longName = String(repeating: "城", count: 80)
        let ics = MeetingCalendarExportService.makeICS(
            event: event(participants: [
                MeetingCalendarParticipant(
                    cityName: longName,
                    cityEn: longName,
                    timezoneId: "Asia/Shanghai"
                )
            ])
        )

        for line in ics.components(separatedBy: "\r\n") where !line.isEmpty {
            XCTAssertLessThanOrEqual(line.utf8.count, 75, "Line exceeds 75 bytes: \(line)")
        }
    }

    func testLegacyRecordWithoutTimezoneDoesNotGuessOffsets() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(participants: [
                MeetingCalendarParticipant(
                    cityName: "Shanghai",
                    cityEn: "Shanghai",
                    timezoneId: nil
                )
            ])
        )

        XCTAssertFalse(ics.contains("UTC+"))
        XCTAssertTrue(ics.contains("\r\nDTSTART:20261107T073000Z\r\n"))
    }

    func testDescriptionOmitsUTCOffsets() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(participants: [
                MeetingCalendarParticipant(
                    cityName: "Kathmandu",
                    cityEn: "Kathmandu",
                    timezoneId: "Asia/Kathmandu"
                )
            ])
        )

        XCTAssertFalse(ics.contains("UTC+"))
        XCTAssertFalse(ics.contains("UTC-"))
    }

    func testDSTTransitionKeepsAbsoluteDuration() {
        let ics = MeetingCalendarExportService.makeICS(
            event: event(
                startDate: date("2026-03-08T06:30:00Z"),
                localTimezoneId: "America/New_York",
                participants: [
                    MeetingCalendarParticipant(
                        cityName: "New York",
                        cityEn: "New York",
                        timezoneId: "America/New_York"
                    )
                ]
            )
        )

        XCTAssertTrue(ics.contains("DTSTART:20260308T063000Z"))
        XCTAssertTrue(ics.contains("DTEND:20260308T073000Z"))
    }

    func testTemporaryFileCanBeCreatedAndRemoved() throws {
        let url = try MeetingCalendarExportService.makeTemporaryFile(event: event())
        defer { MeetingCalendarExportService.removeTemporaryFile(at: url) }

        XCTAssertEqual(url.pathExtension, "ics")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("BEGIN:VCALENDAR"))

        MeetingCalendarExportService.removeTemporaryFile(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    func testMeetingModelKeepsTimezoneIDsAndDefaultsLegacyRecordsToNil() {
        let startDate = date("2026-11-07T07:30:00Z")
        let saved = MeetingModel(
            startDate: startDate,
            durationMinutes: 60,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["Shanghai", "London"],
            participantEnNames: ["Shanghai", "London"],
            participantTimezoneIds: ["Asia/Shanghai", "Europe/London"]
        )
        let legacy = MeetingModel(
            startDate: startDate,
            durationMinutes: 60,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["Shanghai"],
            participantEnNames: ["Shanghai"]
        )

        XCTAssertEqual(saved.participantTimezoneIds, ["Asia/Shanghai", "Europe/London"])
        XCTAssertNil(legacy.participantTimezoneIds)
    }
}
