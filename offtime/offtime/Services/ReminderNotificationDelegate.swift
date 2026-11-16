import UserNotifications

/// 前台收到本地提醒时，仍然展示横幅并播放用户选择的提醒音。
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderNotificationDelegate()
    nonisolated static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner,
        .list,
        .sound
    ]

    private override init() {
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundPresentationOptions
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["notificationType"] as? String == "meetingReminder",
           let rawMeetingID = userInfo["meetingID"] as? String,
           let meetingID = UUID(uuidString: rawMeetingID) {
            Task { @MainActor in
                NotificationNavigationCenter.shared.openMeeting(meetingID)
            }
        }
        completionHandler()
    }
}
