import Foundation
import UserNotifications
import SwiftData

extension Notification.Name {
    static let reminderStoreDidChange = Notification.Name("lt.offtime.reminderStoreDidChange")
}

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
    let weekdayPolicy: CityReminderWeekdayPolicy
    /// 目标城市时区与对应时刻（用于展示与通知正文）
    let targetTimezoneId: String
    let targetHour: Int
    let targetMinute: Int
}

enum CityReminderScheduler {
    private static let weekdayRange = 1...7
    private static let maxSearchDays = 21

    static func nextOccurrence(
        after date: Date,
        timezoneId: String,
        hour: Int,
        minute: Int,
        targetTimezoneId: String,
        weekdayPolicy: CityReminderWeekdayPolicy
    ) -> Date? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        if weekdayPolicy.includesTargetCity,
           TimeZone(identifier: targetTimezoneId) == nil {
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

        guard weekdayPolicy.requiresWeekdayFiltering else {
            return occurrence
        }

        for _ in 0..<maxSearchDays {
            if isAllowedOccurrence(
                at: occurrence,
                timezoneId: timezoneId,
                targetTimezoneId: targetTimezoneId,
                weekdayPolicy: weekdayPolicy
            ) {
                return occurrence
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: occurrence) else {
                return nil
            }
            occurrence = nextDay
        }

        return nil
    }

    /// 按重复规则判断某个具体触发时刻是否应发送提醒。
    static func isAllowedOccurrence(
        at date: Date,
        timezoneId: String,
        targetTimezoneId: String,
        weekdayPolicy: CityReminderWeekdayPolicy
    ) -> Bool {
        switch weekdayPolicy {
        case .everyDay:
            return true
        case .bothCities:
            guard let currentCityIsWeekend = isWeekend(at: date, timezoneId: timezoneId),
                  let targetCityIsWeekend = isWeekend(at: date, timezoneId: targetTimezoneId) else {
                return false
            }
            return !currentCityIsWeekend && !targetCityIsWeekend
        case .currentCity:
            guard let currentCityIsWeekend = isWeekend(at: date, timezoneId: timezoneId) else {
                return false
            }
            return !currentCityIsWeekend
        case .targetCity:
            guard let targetCityIsWeekend = isWeekend(at: date, timezoneId: targetTimezoneId) else {
                return false
            }
            return !targetCityIsWeekend
        }
    }

    static func isWeekend(at date: Date, timezoneId: String) -> Bool? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// 计算可以注册为每周重复通知的本地星期。
    /// 目标城市的星期由本地触发时刻换算得出，因此单城市规则也可能映射到下一天。
    static func repeatWeekdays(
        after date: Date,
        timezoneId: String,
        hour: Int,
        minute: Int,
        targetTimezoneId: String,
        weekdayPolicy: CityReminderWeekdayPolicy
    ) -> [Int] {
        guard weekdayPolicy.requiresWeekdayFiltering,
              let timezone = TimeZone(identifier: timezoneId) else {
            return []
        }
        if weekdayPolicy.includesTargetCity,
           TimeZone(identifier: targetTimezoneId) == nil {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        return weekdayRange.compactMap { weekday in
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let occurrence = calendar.nextDate(
                after: date,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) else {
                return nil
            }

            return isAllowedOccurrence(
                at: occurrence,
                timezoneId: timezoneId,
                targetTimezoneId: targetTimezoneId,
                weekdayPolicy: weekdayPolicy
            ) ? weekday : nil
        }
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
    private static let scheduleVersion = 4

    private let notificationCenter: UserNotificationCenterProtocol
    private let modelContainer: ModelContainer?
    private let now: () -> Date

    init(
        notificationCenter: UserNotificationCenterProtocol = UserNotificationCenterAdapter(),
        modelContainer: ModelContainer? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.notificationCenter = notificationCenter
        self.modelContainer = modelContainer
        self.now = now
    }

    func isNotificationDeliveryAvailable() async -> Bool {
        let status = await notificationCenter.notificationAuthorizationStatus()
        return Self.canDeliverNotifications(for: status)
    }

    static func canDeliverNotifications(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    @discardableResult
    func addReminder(
        cityID: UUID,
        cityName: String,
        timezoneId: String,
        hour: Int,
        minute: Int,
        weekdayPolicy: CityReminderWeekdayPolicy,
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
            weekdayPolicy: weekdayPolicy,
            targetTimezoneId: targetTimezoneId,
            targetHour: targetHour,
            targetMinute: targetMinute
        )

        try await schedule(group)
        upsert(group)
        NotificationCenter.default.post(name: .reminderStoreDidChange, object: nil)
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
            sortBy: [SortDescriptor(\.hour), SortDescriptor(\.minute), SortDescriptor(\.cityName), SortDescriptor(\.id)]
        )
        guard let models = try? fetchModels(fetch) else { return [] }
        return models.map { $0.toGroup() }
    }

    func removeReminder(id: String) async {
        let existing = reminderModel(withID: id)
        if let existing {
            deleteModels(withIDs: [existing.id])
        }
        await cancelScheduledNotifications(for: id)
        NotificationCenter.default.post(name: .reminderStoreDidChange, object: nil)
    }

    func deleteReminders(cityID: UUID) async {
        await deleteReminders(cityIDs: [cityID])
    }

    /// 批量删除多个城市的提醒，统一保存并只发一次变更通知。
    func deleteReminders(cityIDs: [UUID]) async {
        let uniqueCityIDs = Set(cityIDs)
        guard !uniqueCityIDs.isEmpty else { return }

        var reminders: [ReminderModel] = []
        for cityID in uniqueCityIDs {
            let idToFind = cityID
            let fetch = FetchDescriptor<ReminderModel>(
                predicate: #Predicate { $0.cityID == idToFind }
            )
            reminders.append(contentsOf: (try? fetchModels(fetch)) ?? [])
        }
        guard !reminders.isEmpty else { return }

        deleteModels(withIDs: Set(reminders.map(\.id)))
        for reminder in reminders {
            await cancelScheduledNotifications(for: reminder.id.uuidString)
        }
        NotificationCenter.default.post(name: .reminderStoreDidChange, object: nil)
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
        guard Self.canDeliverNotifications(for: authorizationStatus) else {
            await cleanupOrphanedReminders()
            return
        }

        let referenceDate = now()
        for reminder in await allReminders() {
            let expectedIdentifiers = Set(
                scheduledNotificationIdentifiers(for: reminder, after: referenceDate)
            )
            let reminderRequests = requests.filter {
                $0.identifier.hasPrefix("\(reminder.id)-")
            }
            let scheduledIdentifiers = Set(reminderRequests.map(\.identifier))
            let needsContentRefresh = reminderRequests.contains {
                ($0.content.userInfo["scheduleVersion"] as? Int) != Self.scheduleVersion
            }
            if expectedIdentifiers != scheduledIdentifiers || needsContentRefresh {
                try? await schedule(reminder, requestAuthorization: false)
            }
        }

        await cleanupOrphanedReminders()
    }

    // MARK: - Scheduling

    private func schedule(
        _ reminder: CityReminderGroup,
        requestAuthorization: Bool = true
    ) async throws {
        guard let triggerComponents = CityReminderScheduler.triggerComponents(
            hour: reminder.hour,
            minute: reminder.minute,
            timezoneId: reminder.timezoneId
        ) else {
            throw CityReminderError.invalidTimezone
        }

        if requestAuthorization {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                throw CityReminderError.authorizationDenied
            }
        }

        let allIdentifiers = allNotificationIdentifiers(for: reminder.id)
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: allIdentifiers)

        let content = UNMutableNotificationContent()
        let city = cityModel(withID: reminder.cityID)
        content.title = CityDisplay.primaryName(
            cityName: reminder.cityName,
            cityEn: city?.cityEn ?? reminder.cityName
        )
        content.body = notificationBody(
            targetTimezoneId: reminder.targetTimezoneId,
            targetHour: reminder.targetHour,
            targetMinute: reminder.targetMinute
        )
        content.sound = .default
        content.userInfo = userInfo(for: reminder)

        let weekdays: [Int?]
        if reminder.weekdayPolicy.requiresWeekdayFiltering {
            let repeatDays = CityReminderScheduler.repeatWeekdays(
                after: now(),
                timezoneId: reminder.timezoneId,
                hour: reminder.hour,
                minute: reminder.minute,
                targetTimezoneId: reminder.targetTimezoneId,
                weekdayPolicy: reminder.weekdayPolicy
            )
            guard !repeatDays.isEmpty else {
                throw CityReminderError.invalidTimezone
            }
            weekdays = repeatDays.map(Optional.some)
        } else {
            weekdays = [nil]
        }

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
        let identifiers = allNotificationIdentifiers(for: reminderID)
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        await notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func allNotificationIdentifiers(for reminderID: String) -> [String] {
        ["\(reminderID)-daily"] + (1...7).map { "\(reminderID)-\($0)" }
    }

    private func scheduledNotificationIdentifiers(
        for reminder: CityReminderGroup,
        after date: Date
    ) -> [String] {
        guard reminder.weekdayPolicy.requiresWeekdayFiltering else {
            return ["\(reminder.id)-daily"]
        }

        return CityReminderScheduler.repeatWeekdays(
            after: date,
            timezoneId: reminder.timezoneId,
            hour: reminder.hour,
            minute: reminder.minute,
            targetTimezoneId: reminder.targetTimezoneId,
            weekdayPolicy: reminder.weekdayPolicy
        ).map { "\(reminder.id)-\($0)" }
    }

    private func userInfo(for reminder: CityReminderGroup) -> [String: Any] {
        [
            "reminderID": reminder.id,
            "cityID": reminder.cityID.uuidString,
            "cityName": reminder.cityName,
            "timezoneId": reminder.timezoneId,
            "hour": reminder.hour,
            "minute": reminder.minute,
            "weekdayPolicy": reminder.weekdayPolicy.rawValue,
            "weekdaysOnly": reminder.weekdayPolicy.legacyWeekdaysOnly,
            "targetTimezoneId": reminder.targetTimezoneId,
            "targetHour": reminder.targetHour,
            "targetMinute": reminder.targetMinute,
            "scheduleVersion": Self.scheduleVersion
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
              let targetTimezoneId = userInfo["targetTimezoneId"] as? String,
              let targetHour = userInfo["targetHour"] as? Int,
              let targetMinute = userInfo["targetMinute"] as? Int else {
            return nil
        }
        let weekdayPolicy = (userInfo["weekdayPolicy"] as? String)
            .flatMap(CityReminderWeekdayPolicy.init(rawValue:))
            ?? CityReminderWeekdayPolicy(legacyWeekdaysOnly: userInfo["weekdaysOnly"] as? Bool ?? false)

        return CityReminderGroup(
            id: reminderID,
            cityID: cityID,
            cityName: cityName,
            timezoneId: timezoneId,
            hour: hour,
            minute: minute,
            weekdayPolicy: weekdayPolicy,
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

    private func cityModel(withID id: UUID) -> CityModel? {
        let fetch = FetchDescriptor<CityModel>(predicate: #Predicate { $0.id == id })
        return try? fetchModels(fetch).first
    }

    private func upsert(_ reminder: CityReminderGroup) {
        guard let reminderID = UUID(uuidString: reminder.id) else { return }
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let existing = reminderModel(withID: reminder.id)
        let model = existing ?? ReminderModel(id: reminderID, cityID: reminder.cityID, cityName: reminder.cityName, timezoneId: reminder.timezoneId, hour: reminder.hour, minute: reminder.minute, weekdayPolicy: reminder.weekdayPolicy, targetTimezoneId: reminder.targetTimezoneId, targetHour: reminder.targetHour, targetMinute: reminder.targetMinute)

        model.cityID = reminder.cityID
        model.cityName = reminder.cityName
        model.timezoneId = reminder.timezoneId
        model.hour = reminder.hour
        model.minute = reminder.minute
        model.weekdaysOnly = reminder.weekdayPolicy.legacyWeekdaysOnly
        model.weekdayPolicyRaw = reminder.weekdayPolicy.rawValue
        model.targetTimezoneId = reminder.targetTimezoneId
        model.targetHour = reminder.targetHour
        model.targetMinute = reminder.targetMinute
        if existing == nil {
            context.insert(model)
        }
        try? context.save()
    }

    private func deleteModels(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let reminders = (try? context.fetch(FetchDescriptor<ReminderModel>())) ?? []
        for reminder in reminders where ids.contains(reminder.id) {
            context.delete(reminder)
        }
        try? context.save()
    }

    private func cleanupOrphanedReminders() async {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        let cities = (try? context.fetch(FetchDescriptor<CityModel>())) ?? []
        let validCityIDs = Set(cities.map(\.id))
        let reminders = (try? context.fetch(FetchDescriptor<ReminderModel>())) ?? []

        let orphaned = reminders.filter { !validCityIDs.contains($0.cityID) }
        guard !orphaned.isEmpty else { return }

        for reminder in orphaned {
            context.delete(reminder)
        }
        try? context.save()

        for reminder in orphaned {
            await cancelScheduledNotifications(for: reminder.id.uuidString)
        }
    }

    private func notificationBody(
        targetTimezoneId: String,
        targetHour: Int,
        targetMinute: Int
    ) -> String {
        let timezone = TimeZone(identifier: targetTimezoneId) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        var components = calendar.dateComponents([.year, .month, .day], from: now())
        components.hour = targetHour
        components.minute = targetMinute
        guard let date = calendar.date(from: components) else {
            return String(format: "%02d:%02d", targetHour, targetMinute)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timezone

        return String(
            format: String(localized: "city.reminder.contactable.body"),
            formatter.string(from: date)
        )
    }
}
