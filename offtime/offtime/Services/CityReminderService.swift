import Foundation
import UserNotifications

enum CityReminderError: LocalizedError {
    case authorizationDenied
    case invalidTimezone

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return String(localized: "city.reminder.error.authorization")
        case .invalidTimezone:
            return String(localized: "city.reminder.error.timezone")
        }
    }
}

struct CityReminderGroup: Identifiable, Equatable {
    let id: String
    let cityID: UUID
    let cityName: String
    /// 触发时区（当前城市）
    let timezoneId: String
    let hour: Int
    let minute: Int
    let weekdaysOnly: Bool
    /// 目标城市时区与对应时刻（用于展示与通知正文）
    let targetTimezoneId: String
    let targetHour: Int
    let targetMinute: Int
}

enum CityReminderScheduler {
    static func nextOccurrence(
        after date: Date,
        timezoneId: String,
        hour: Int,
        minute: Int,
        weekdaysOnly: Bool
    ) -> Date? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard var occurrence = calendar.date(from: components) else {
            return nil
        }

        if occurrence <= date {
            occurrence = calendar.date(byAdding: .day, value: 1, to: occurrence) ?? occurrence
        }

        if weekdaysOnly {
            while calendar.component(.weekday, from: occurrence) == 1
                || calendar.component(.weekday, from: occurrence) == 7 {
                occurrence = calendar.date(byAdding: .day, value: 1, to: occurrence) ?? occurrence
            }
        }

        return occurrence
    }

    static func triggerComponents(
        hour: Int,
        minute: Int,
        timezoneId: String,
        weekday: Int? = nil
    ) -> DateComponents? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.timeZone = timezone
        if let weekday {
            components.weekday = weekday
        }
        return components
    }
}

final class CityReminderService {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func addReminder(
        cityID: UUID,
        cityName: String,
        timezoneId: String,
        hour: Int,
        minute: Int,
        weekdaysOnly: Bool,
        targetTimezoneId: String,
        targetHour: Int,
        targetMinute: Int
    ) async throws -> CityReminderGroup {
        guard let triggerComponents = CityReminderScheduler.triggerComponents(
                  hour: hour,
                  minute: minute,
                  timezoneId: timezoneId
              ) else {
            throw CityReminderError.invalidTimezone
        }

        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else {
            throw CityReminderError.authorizationDenied
        }

        let reminderID = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = cityName
        content.body = notificationBody(
            targetTimezoneId: targetTimezoneId,
            targetHour: targetHour,
            targetMinute: targetMinute
        )
        content.sound = .default
        content.userInfo = [
            "reminderID": reminderID,
            "cityID": cityID.uuidString,
            "cityName": cityName,
            "timezoneId": timezoneId,
            "hour": hour,
            "minute": minute,
            "weekdaysOnly": weekdaysOnly,
            "targetTimezoneId": targetTimezoneId,
            "targetHour": targetHour,
            "targetMinute": targetMinute
        ]

        let weekdays = weekdaysOnly ? [2, 3, 4, 5, 6] : [nil]
        for weekday in weekdays {
            var components = triggerComponents
            components.weekday = weekday

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )
            let weekdayName = weekday.map { "\($0)" } ?? "daily"
            let request = UNNotificationRequest(
                identifier: "\(reminderID)-\(weekdayName)",
                content: content,
                trigger: trigger
            )
            try await notificationCenter.add(request)
        }

        return CityReminderGroup(
            id: reminderID,
            cityID: cityID,
            cityName: cityName,
            timezoneId: timezoneId,
            hour: hour,
            minute: minute,
            weekdaysOnly: weekdaysOnly,
            targetTimezoneId: targetTimezoneId,
            targetHour: targetHour,
            targetMinute: targetMinute
        )
    }

    func reminders(for cityID: UUID) async -> [CityReminderGroup] {
        let requests = await notificationCenter.pendingNotificationRequests()
        let groups = requests.compactMap { request -> CityReminderGroup? in
            let userInfo = request.content.userInfo
            guard let reminderID = userInfo["reminderID"] as? String,
                  let storedCityID = userInfo["cityID"] as? String,
                  storedCityID == cityID.uuidString,
                  let cityName = userInfo["cityName"] as? String,
                  let timezoneId = userInfo["timezoneId"] as? String,
                  let hour = userInfo["hour"] as? Int,
                  let minute = userInfo["minute"] as? Int,
                  let weekdaysOnly = userInfo["weekdaysOnly"] as? Bool,
                  let targetTimezoneId = userInfo["targetTimezoneId"] as? String,
                  let targetHour = userInfo["targetHour"] as? Int,
                  let targetMinute = userInfo["targetMinute"] as? Int else {
                return nil
            }

            return CityReminderGroup(
                id: reminderID,
                cityID: cityID,
                cityName: cityName,
                timezoneId: timezoneId,
                hour: hour,
                minute: minute,
                weekdaysOnly: weekdaysOnly,
                targetTimezoneId: targetTimezoneId,
                targetHour: targetHour,
                targetMinute: targetMinute
            )
        }

        return Array(Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            .values)
            .sorted {
                if $0.hour != $1.hour {
                    return $0.hour < $1.hour
                }
                if $0.minute != $1.minute {
                    return $0.minute < $1.minute
                }
                return $0.id < $1.id
            }
    }

    func removeReminder(id: String) async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let identifiers = requests
            .filter { $0.content.userInfo["reminderID"] as? String == id }
            .map(\.identifier)

        guard !identifiers.isEmpty else {
            return
        }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func notificationBody(
        targetTimezoneId: String,
        targetHour: Int,
        targetMinute: Int
    ) -> String {
        let timezone = TimeZone(identifier: targetTimezoneId) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = targetHour
        components.minute = targetMinute
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", targetHour, targetMinute)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = timezone

        return String(
            format: String(localized: "city.reminder.contactable.body"),
            formatter.string(from: date)
        )
    }
}
