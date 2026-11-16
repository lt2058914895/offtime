import UserNotifications
import XCTest
@testable import offtime

@MainActor
private final class MeetingNotificationCenterMock: UserNotificationCenterProtocol {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var requests: [UNNotificationRequest] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
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
        let service = MeetingReminderService(center: center)
        let meeting = MeetingModel(
            startDate: Date().addingTimeInterval(3_600),
            durationMinutes: 30,
            localTimezoneId: "Asia/Shanghai",
            participantNames: ["上海", "伦敦"],
            participantEnNames: ["Shanghai", "London"],
            participantTimezoneIds: ["Asia/Shanghai", "Europe/London"],
            title: "跨城市沟通",
            reminderLeadTimeMinutes: 10,
            scheduleSource: .inAppReminder
        )

        let identifier = try await service.schedule(for: meeting)
        let expectedIdentifier = MeetingReminderService.notificationIdentifier(for: meeting.id)

        XCTAssertEqual(identifier, expectedIdentifier)
        XCTAssertEqual(center.requests.count, 1)
        XCTAssertEqual(center.requests.first?.identifier, expectedIdentifier)
        XCTAssertEqual(center.requests.first?.content.title, "跨城市沟通")

        let trigger = try XCTUnwrap(
            center.requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        )
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.timeInterval, 3_000, accuracy: 3)

        await service.cancel(for: meeting.id)
        XCTAssertTrue(center.requests.isEmpty)
    }

}
