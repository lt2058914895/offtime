import Foundation
import UserNotifications

enum MeetingReminderServiceError: LocalizedError, Equatable {
    case authorizationDenied
    case reminderDatePassed
    case schedulingFailed

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return String(
                format: String(localized: "meeting.reminder.error.authorization"),
                AppDisplay.name
            )
        case .reminderDatePassed:
            return String(localized: "meeting.reminder.error.timePassed")
        case .schedulingFailed:
            return String(localized: "meeting.reminder.error.schedule")
        }
    }

    var requiresSettingsAction: Bool {
        self == .authorizationDenied
    }
}

@MainActor
final class MeetingReminderService {
    static let shared = MeetingReminderService()

    private let center: UserNotificationCenterProtocol

    init(center: UserNotificationCenterProtocol? = nil) {
        self.center = center ?? UserNotificationCenterAdapter()
    }

    func schedule(for meeting: MeetingModel) async throws -> String? {
        guard let leadTimeMinutes = meeting.reminderLeadTimeMinutes else {
            await cancel(for: meeting.id)
            return nil
        }

        let fireDate = meeting.startDate.addingTimeInterval(
            -Double(max(leadTimeMinutes, 0)) * 60
        )
        let interval = fireDate.timeIntervalSinceNow
        guard interval > 1 else {
            throw MeetingReminderServiceError.reminderDatePassed
        }

        let status = await center.notificationAuthorizationStatus()
        let authorized: Bool
        switch status {
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .notDetermined:
            authorized = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }
        guard authorized else {
            throw MeetingReminderServiceError.authorizationDenied
        }

        let content = UNMutableNotificationContent()
        let trimmedTitle = meeting.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        content.title = trimmedTitle.isEmpty
            ? String(localized: "meeting.ics.summary.empty")
            : trimmedTitle
        content.body = reminderBody(for: meeting)
        content.sound = .default
        content.userInfo = [
            "meetingID": meeting.id.uuidString,
            "notificationType": "meetingReminder"
        ]

        let identifier = Self.notificationIdentifier(for: meeting.id)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
        )

        do {
            try await center.add(request)
            return identifier
        } catch {
            throw MeetingReminderServiceError.schedulingFailed
        }
    }

    func cancel(for meetingID: UUID) async {
        let identifier = Self.notificationIdentifier(for: meetingID)
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])
        await center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func notificationIdentifier(for meetingID: UUID) -> String {
        "meeting-reminder-\(meetingID.uuidString)"
    }

    private func reminderBody(for meeting: MeetingModel) -> String {
        let endDate = meeting.startDate.addingTimeInterval(
            Double(meeting.durationMinutes) * 60
        )
        let timezone = TimeZone(identifier: meeting.localTimezoneId) ?? .current
        let timeText = DateDisplayFormat.timeRange(
            start: meeting.startDate,
            end: endDate,
            timezone: timezone
        )
        let cityText = meeting.participantNames.joined(
            separator: String(localized: "meeting.slots.constraints.join")
        )
        guard !cityText.isEmpty else {
            return timeText
        }
        return "\(cityText) · \(timeText)"
    }
}
