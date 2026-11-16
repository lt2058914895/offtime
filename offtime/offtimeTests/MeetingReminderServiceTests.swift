import UserNotifications
import SwiftData
import XCTest
@testable import offtime

@MainActor
private final class MeetingNotificationCenterMock: UserNotificationCenterProtocol {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var requests: [UNNotificationRequest] = []
    var authorizationRequestCount = 0

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequestCount += 1
        return true
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        requests
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }
}

private final class MeetingSoundProviderMock: ReminderSoundProviding {
    var requestedSounds: [ReminderSound] = []

    func notificationSound(for sound: ReminderSound) -> UNNotificationSound? {
        requestedSounds.append(sound)
        return UNNotificationSound(
            named: UNNotificationSoundName(rawValue: "\(sound.rawValue).caf")
        )
    }

    func fingerprint(for sound: ReminderSound) -> String {
        sound.rawValue
    }
}

@MainActor
final class MeetingReminderServiceTests: XCTestCase {
    func testMeetingModelSupportsNewScheduleMetadataAndLegacyDefault() {
        let meeting = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海", "伦敦"],
            participantEnNames: ["Shanghai", "London"],
            participantTimezoneIds: ["Asia/Shanghai", "Europe/London"],
            title: "跨城市沟通",
            notes: "确认项目进度",
            reminderLeadTimeMinutes: 10,
            scheduleSource: .inAppReminder,
            notificationIdentifier: "notification-id"
        )

        XCTAssertEqual(meeting.scheduleSource, .inAppReminder)
        XCTAssertEqual(meeting.title, "跨城市沟通")
        XCTAssertEqual(meeting.reminderLeadTimeMinutes, 10)
        XCTAssertEqual(meeting.notificationIdentifier, "notification-id")

        let defaultSource = MeetingModel(
            startDate: Date(),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海"]
        )
        XCTAssertEqual(defaultSource.scheduleSource, .inAppReminder)
    }

    func testInAppScheduleCreatesAndCancelsLocalNotification() async throws {
        let center = MeetingNotificationCenterMock()
        let soundProvider = MeetingSoundProviderMock()
        let service = MeetingReminderService(
            center: center,
            soundProvider: soundProvider,
            resolvedSound: { .gentleMarimba }
        )
        let meeting = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海", "伦敦"],
            participantEnNames: ["Shanghai", "London"],
            participantTimezoneIds: ["Asia/Shanghai", "Europe/London"],
            title: "跨城市沟通",
            notes: "确认项目进度",
            reminderLeadTimeMinutes: 10,
            scheduleSource: .inAppReminder
        )

        let identifier = try await service.schedule(for: meeting)
        let expectedIdentifier = MeetingReminderService.notificationIdentifier(for: meeting.id)

        XCTAssertEqual(identifier, expectedIdentifier)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.requests.first?.identifier, expectedIdentifier)
        XCTAssertEqual(center.requests.first?.content.title, "跨城市沟通")
        XCTAssertEqual(
            center.requests.first?.content.body,
            "\(String(format: String(localized: "meeting.reminder.body.minutesRemaining"), 10))\n确认项目进度"
        )
        XCTAssertEqual(soundProvider.requestedSounds, [.gentleMarimba])
        XCTAssertEqual(
            center.requests.first?.content.userInfo["reminderSoundID"] as? String,
            ReminderSound.gentleMarimba.rawValue
        )

        let trigger = try XCTUnwrap(
            center.requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        )
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.timeInterval, 3_000, accuracy: 3)

        await service.cancel(for: meeting.id)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testMeetingStartedReminderUsesStartedBodyAndNotes() async throws {
        let center = MeetingNotificationCenterMock()
        let service = MeetingReminderService(
            center: center,
            resolvedSound: { .system }
        )
        let meeting = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海"],
            title: "项目沟通",
            notes: "打开会议链接",
            reminderLeadTimeMinutes: 0
        )

        _ = try await service.schedule(for: meeting)
        XCTAssertEqual(
            center.requests.first?.content.body,
            "\(String(localized: "meeting.reminder.body.started"))\n打开会议链接"
        )
    }

    func testMeetingWithoutReminderDoesNotScheduleOrRequestAuthorization() async throws {
        let center = MeetingNotificationCenterMock()
        center.authorizationStatus = .notDetermined
        let service = MeetingReminderService(center: center)
        let meeting = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海"],
            reminderLeadTimeMinutes: nil
        )

        let identifier = try await service.schedule(for: meeting)
        XCTAssertNil(identifier)
        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertEqual(center.authorizationRequestCount, 0)
    }

    func testReminderTimingRejectsOptionsThatHaveAlreadyPassed() {
        let now = Date()
        let meetingStart = now.addingTimeInterval(20 * 60)

        XCTAssertFalse(
            MeetingReminderTiming.isAvailable(
                startDate: meetingStart,
                leadTimeMinutes: 30,
                now: now
            )
        )
        XCTAssertTrue(
            MeetingReminderTiming.isAvailable(
                startDate: meetingStart,
                leadTimeMinutes: 15,
                now: now
            )
        )
        XCTAssertTrue(
            MeetingReminderTiming.isAvailable(
                startDate: meetingStart,
                leadTimeMinutes: 0,
                now: now
            )
        )
    }

    func testPastReminderDoesNotCreateNotification() async {
        let center = MeetingNotificationCenterMock()
        let service = MeetingReminderService(center: center)
        let meeting = MeetingModel(
            startDate: Date().addingTimeInterval(20 * 60),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海"],
            reminderLeadTimeMinutes: 30
        )

        do {
            _ = try await service.schedule(for: meeting)
            XCTFail("Expected the past reminder to be rejected")
        } catch let error as MeetingReminderServiceError {
            XCTAssertEqual(error, .reminderDatePassed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testRescheduleAllRefreshesOnlyUpcomingInAppReminders() async throws {
        let container = try ModelContainer(
            for: MeetingModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let center = MeetingNotificationCenterMock()
        let soundProvider = MeetingSoundProviderMock()
        let service = MeetingReminderService(
            center: center,
            soundProvider: soundProvider,
            resolvedSound: { .alarm }
        )
        let upcoming = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海"],
            reminderLeadTimeMinutes: 10
        )
        let noReminder = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海"],
            reminderLeadTimeMinutes: nil
        )
        context.insert(upcoming)
        context.insert(noReminder)
        try context.save()

        let report = await service.rescheduleAll(in: container)
        XCTAssertEqual(report.scheduledCount, 1)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.requests.first?.identifier, upcoming.notificationIdentifier)
        XCTAssertEqual(soundProvider.requestedSounds, [.alarm])
    }

}
