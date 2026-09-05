import Foundation
import UserNotifications
import SwiftData

protocol UserNotificationCenterProtocol {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
    func notificationAuthorizationStatus() async -> UNAuthorizationStatus
}

final class UserNotificationCenterAdapter: UserNotificationCenterProtocol {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}

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

@MainActor
final class CityReminderService {
    private let notificationCenter: UserNotificationCenterProtocol
    private let modelContainer: ModelContainer?

    init(
        notificationCenter: UserNotificationCenterProtocol = UserNotificationCenterAdapter(),
        modelContainer: ModelContainer? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.modelContainer = modelContainer
    }

    @discardableResult
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
        let reminderID = UUID().uuidString
        let group = CityReminderGroup(
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

        try await schedule(group)
        upsert(group)
        return group
    }

    func reminders(for cityID: UUID) async -> [CityReminderGroup] {
        let id = cityID
        var fetch = FetchDescriptor<ReminderModel>(
            predicate: #Predicate { $0.cityID == id },
            sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute), SortDescriptor(\.id)]
        )
        fetch.fetchLimit = 64
        guard let models = try? fetchModels(fetch) else { return [] }
        return models.map { $0.toGroup() }
    }

    /// 获取所有城市的提醒列表
    func allReminders() async -> [CityReminderGroup] {
        let fetch = FetchDescriptor<ReminderModel>(
            sortBy: [SortDescriptor(\.cityName), SortDescriptor(\.hour), SortDescriptor(\.minute), SortDescriptor(\.id)]
        )
        guard let models = try? fetchModels(fetch) else { return [] }
        return models.map { $0.toGroup() }
    }

    func removeReminder(id: String) async {
        if let reminderID = UUID(uuidString: id) {
            deleteModel(id: reminderID)
        }
        await cancelScheduledNotifications(for: id)
    }

    func deleteReminders(cityID: UUID) async {
        let cityIDToFind = cityID
        let fetch = FetchDescriptor<ReminderModel>(
            predicate: #Predicate { $0.cityID == cityIDToFind }
        )
        let reminders = (try? fetchModels(fetch)) ?? []
        for reminder in reminders {
            deleteModel(id: reminder.id)
        }
        for reminder in reminders {
            await cancelScheduledNotifications(for: reminder.id.uuidString)
        }
    }

    /// 启动时同步两套存储：
    /// 1. 把旧版本仅存在于通知中心的提醒迁移到 SwiftData。
    /// 2. 恢复被用户或系统删除的待发通知。
    /// 3. 清理城市已经不存在后的孤立提醒。
    func synchronize() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let pendingGroups = requests.compactMap(Self.group(from:))
        for group in pendingGroups where reminderModel(withID: group.id) == nil {
            upsert(group)
        }

        let authorizationStatus = await notificationCenter.notificationAuthorizationStatus()
        guard authorizationStatus == .authorized
                || authorizationStatus == .provisional
                || authorizationStatus == .ephemeral else {
            cleanupOrphanedReminders()
            return
        }

        let pendingIDs = Set(requests.map(\.identifier))
        for reminder in await allReminders() {
            let identifiers = Set(notificationIdentifiers(for: reminder.id, weekdaysOnly: reminder.weekdaysOnly))
            guard identifiers.isDisjoint(with: pendingIDs)
                    || !identifiers.isSubset(of: pendingIDs) else {
                continue
            }
            try? await schedule(reminder, requestAuthorization: false)
        }

        cleanupOrphanedReminders()
    }

    // MARK: - Scheduling

    private func schedule(
        _ reminder: CityReminderGroup,
        requestAuthorization: Bool = true
    ) async throws {
        guard CityReminderScheduler.triggerComponents(
            hour: reminder.hour,
            minute: reminder.minute,
            timezoneId: reminder.timezoneId
        ) != nil else {
            throw CityReminderError.invalidTimezone
        }

        if requestAuthorization {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                throw CityReminderError.authorizationDenied
            }
        }

        let identifiers = notificationIdentifiers(for: reminder.id, weekdaysOnly: reminder.weekdaysOnly)
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard let triggerComponents = CityReminderScheduler.triggerComponents(
            hour: reminder.hour,
            minute: reminder.minute,
            timezoneId: reminder.timezoneId
        ) else {
            throw CityReminderError.invalidTimezone
        }

        let content = UNMutableNotificationContent()
        content.title = reminder.cityName
        content.body = notificationBody(
            targetTimezoneId: reminder.targetTimezoneId,
            targetHour: reminder.targetHour,
            targetMinute: reminder.targetMinute
        )
        content.sound = .default
        content.userInfo = userInfo(for: reminder)

        let weekdays = reminder.weekdaysOnly ? [2, 3, 4, 5, 6] : [nil]
        var addedIdentifiers: [String] = []
        do {
            for weekday in weekdays {
                var components = triggerComponents
                components.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let weekdayName = weekday.map { "\($0)" } ?? "daily"
                let identifier = "\(reminder.id)-\(weekdayName)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                try await notificationCenter.add(request)
                addedIdentifiers.append(identifier)
            }
        } catch {
            await notificationCenter.removePendingNotificationRequests(withIdentifiers: addedIdentifiers)
            throw error
        }
    }

    private func cancelScheduledNotifications(for reminderID: String) async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let identifiers = requests
            .filter { $0.content.userInfo["reminderID"] as? String == reminderID }
            .map(\.identifier)

        guard !identifiers.isEmpty else { return }
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        await notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func notificationIdentifiers(for reminderID: String, weekdaysOnly: Bool) -> [String] {
        weekdaysOnly
            ? [2, 3, 4, 5, 6].map { "\(reminderID)-\($0)" }
            : ["\(reminderID)-daily"]
    }

    private func userInfo(for reminder: CityReminderGroup) -> [String: Any] {
        [
            "reminderID": reminder.id,
            "cityID": reminder.cityID.uuidString,
            "cityName": reminder.cityName,
            "timezoneId": reminder.timezoneId,
            "hour": reminder.hour,
            "minute": reminder.minute,
            "weekdaysOnly": reminder.weekdaysOnly,
            "targetTimezoneId": reminder.targetTimezoneId,
            "targetHour": reminder.targetHour,
            "targetMinute": reminder.targetMinute
        ]
    }

    static func group(from request: UNNotificationRequest) -> CityReminderGroup? {
        let userInfo = request.content.userInfo
        guard let reminderID = userInfo["reminderID"] as? String,
              let storedCityID = userInfo["cityID"] as? String,
              let cityID = UUID(uuidString: storedCityID),
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

    // MARK: - Persistence

    private func fetchModels<T>(_ fetch: FetchDescriptor<T>) throws -> [T] where T: PersistentModel {
        guard let modelContainer else { return [] }
        let context = modelContainer.mainContext
        return try context.fetch(fetch)
    }

    private func reminderModel(withID id: String) -> ReminderModel? {
        guard let reminderID = UUID(uuidString: id) else { return nil }
        let fetch = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == reminderID })
        return try? fetchModels(fetch).first
    }

    private func upsert(_ reminder: CityReminderGroup) {
        guard let reminderID = UUID(uuidString: reminder.id) else { return }
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let existing = reminderModel(withID: reminder.id)
        let model = existing ?? ReminderModel(id: reminderID, cityID: reminder.cityID, cityName: reminder.cityName, timezoneId: reminder.timezoneId, hour: reminder.hour, minute: reminder.minute, weekdaysOnly: reminder.weekdaysOnly, targetTimezoneId: reminder.targetTimezoneId, targetHour: reminder.targetHour, targetMinute: reminder.targetMinute)

        model.cityID = reminder.cityID
        model.cityName = reminder.cityName
        model.timezoneId = reminder.timezoneId
        model.hour = reminder.hour
        model.minute = reminder.minute
        model.weekdaysOnly = reminder.weekdaysOnly
        model.targetTimezoneId = reminder.targetTimezoneId
        model.targetHour = reminder.targetHour
        model.targetMinute = reminder.targetMinute
        if existing == nil {
            context.insert(model)
        }
        try? context.save()
    }

    private func deleteModel(id: UUID) {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let fetch = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id })
        for reminder in (try? context.fetch(fetch)) ?? [] {
            context.delete(reminder)
        }
        try? context.save()
    }

    private func cleanupOrphanedReminders() {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let cities = (try? context.fetch(FetchDescriptor<CityModel>())) ?? []
        let validCityIDs = Set(cities.map(\.id))
        let reminders = (try? context.fetch(FetchDescriptor<ReminderModel>())) ?? []

        for reminder in reminders where !validCityIDs.contains(reminder.cityID) {
            context.delete(reminder)
            let reminderID = reminder.id.uuidString
            Task {
                await cancelScheduledNotifications(for: reminderID)
            }
        }
        try? context.save()
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
        formatter.dateFormat = "yyyy/MM/dd EEE HH:mm"
        formatter.timeZone = timezone

        return String(
            format: String(localized: "city.reminder.contactable.body"),
            formatter.string(from: date)
        )
    }
}
