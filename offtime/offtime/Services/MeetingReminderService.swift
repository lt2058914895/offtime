import Foundation
import SwiftData
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

enum MeetingReminderTiming {
    static func fireDate(
        startDate: Date,
        leadTimeMinutes: Int
    ) -> Date {
        startDate.addingTimeInterval(-Double(max(leadTimeMinutes, 0)) * 60)
    }

    static func isAvailable(
        startDate: Date,
        leadTimeMinutes: Int,
        now: Date = Date()
    ) -> Bool {
        fireDate(
            startDate: startDate,
            leadTimeMinutes: leadTimeMinutes
        ).timeIntervalSince(now) > 1
    }
}

@MainActor
final class MeetingReminderService {
    static let shared = MeetingReminderService()

    private let center: UserNotificationCenterProtocol
    private let soundProvider: ReminderSoundProviding
    private let resolvedSound: () -> ReminderSound

    init(
        center: UserNotificationCenterProtocol? = nil,
        soundProvider: ReminderSoundProviding = BuiltInReminderSoundProvider(),
        resolvedSound: (() -> ReminderSound)? = nil
    ) {
        self.center = center ?? UserNotificationCenterAdapter()
        self.soundProvider = soundProvider
        self.resolvedSound = resolvedSound ?? {
            ReminderSoundPreferences.resolvedDefault(
                isProUnlocked: ProAccessService.shared.isUnlocked
            )
        }
    }

    func schedule(for meeting: MeetingModel) async throws -> String? {
        guard let leadTimeMinutes = meeting.reminderLeadTimeMinutes else {
            await cancel(for: meeting.id)
            return nil
        }

        let fireDate = MeetingReminderTiming.fireDate(
            startDate: meeting.startDate,
            leadTimeMinutes: leadTimeMinutes
        )
        guard MeetingReminderTiming.isAvailable(
            startDate: meeting.startDate,
            leadTimeMinutes: leadTimeMinutes
        ) else {
            throw MeetingReminderServiceError.reminderDatePassed
        }
        let interval = fireDate.timeIntervalSinceNow

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
        content.body = reminderBody(
            for: meeting,
            leadTimeMinutes: leadTimeMinutes
        )
        let sound = resolvedSound()
        content.sound = soundProvider.notificationSound(for: sound)
        content.userInfo = [
            "meetingID": meeting.id.uuidString,
            "notificationType": "meetingReminder",
            "reminderSoundID": sound.rawValue
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

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationAuthorizationStatus()
    }

    /// 全局提醒音效变化后，重建所有仍有效的应用内日程通知。
    @discardableResult
    func rescheduleAll(in modelContainer: ModelContainer) async -> ReminderSchedulingReport {
        var report = ReminderSchedulingReport()
        switch await center.notificationAuthorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            report.skippedForAuthorization = true
            return report
        @unknown default:
            report.skippedForAuthorization = true
            return report
        }

        let context = modelContainer.mainContext
        guard let meetings = try? context.fetch(FetchDescriptor<MeetingModel>()) else {
            return report
        }

        var didChange = false
        for meeting in meetings
        where meeting.scheduleSource == .inAppReminder
            && meeting.reminderLeadTimeMinutes != nil {
            let leadTimeMinutes = meeting.reminderLeadTimeMinutes ?? 0
            let fireDate = MeetingReminderTiming.fireDate(
                startDate: meeting.startDate,
                leadTimeMinutes: leadTimeMinutes
            )
            guard fireDate > Date() else { continue }

            do {
                meeting.notificationIdentifier = try await schedule(for: meeting)
                report.scheduledCount += 1
                didChange = true
            } catch let error as MeetingReminderServiceError {
                if error != .reminderDatePassed {
                    report.failures.append(error.localizedDescription)
                }
            } catch {
                report.failures.append(error.localizedDescription)
            }
        }

        if didChange {
            try? context.save()
        }
        return report
    }

    private func reminderBody(
        for meeting: MeetingModel,
        leadTimeMinutes: Int
    ) -> String {
        let status = reminderStatusText(for: leadTimeMinutes)
        let notes = meeting.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? status : "\(status)\n\(notes)"
    }

    private func reminderStatusText(for minutes: Int) -> String {
        if minutes == 0 {
            return String(localized: "meeting.reminder.body.started")
        }
        if minutes % 10_080 == 0 {
            return String(
                format: String(localized: "meeting.reminder.body.weeksRemaining"),
                minutes / 10_080
            )
        }
        if minutes % 1_440 == 0 {
            return String(
                format: String(localized: "meeting.reminder.body.daysRemaining"),
                minutes / 1_440
            )
        }
        if minutes % 60 == 0 {
            return String(
                format: String(localized: "meeting.reminder.body.hoursRemaining"),
                minutes / 60
            )
        }
        return String(
            format: String(localized: "meeting.reminder.body.minutesRemaining"),
            minutes
        )
    }
}
