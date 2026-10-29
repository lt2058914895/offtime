import SwiftUI
import Combine

@MainActor
final class ReminderListViewModel: ObservableObject {
    @Published var reminders: [CityReminderGroup] = []
    @Published var isLoading = false
    @Published private(set) var isNotificationDeliveryAvailable = true
    @Published private(set) var updatingReminderIDs: Set<String> = []
    @Published private(set) var pausingReminderIDs: Set<String> = []
    @Published var errorMessage: String?

    private let reminderService: CityReminderService
    private let cityService = CityService.shared
    private let timezoneService = TimezoneService.shared

    /// 城市 ID → CityModel 缓存，用于 section header 展示国旗、国家、UTC、时差、DST
    private var cityCache: [UUID: CityModel] = [:]

    init(reminderService: CityReminderService? = nil) {
        self.reminderService = reminderService ?? CityReminderService(
            modelContainer: CityService.shared.modelContainer
        )
    }

    func loadReminders() async {
        isLoading = true
        reminders = await reminderService.allReminders()
        isNotificationDeliveryAvailable = await reminderService.isNotificationDeliveryAvailable()
        loadCityCache()
        isLoading = false
    }

    func refreshNotificationAvailability() async {
        isNotificationDeliveryAvailable = await reminderService.isNotificationDeliveryAvailable()
    }

    func deleteReminder(_ reminder: CityReminderGroup) async {
        await reminderService.removeReminder(id: reminder.id)
        reminders.removeAll { $0.id == reminder.id }
    }

    func updateReminderPolicy(_ reminder: CityReminderGroup, to policy: CityReminderWeekdayPolicy) async {
        guard beginUpdate(for: reminder.id, showsPauseProgress: false) else { return }
        defer { endUpdate(for: reminder.id) }

        do {
            try await reminderService.updateReminderPolicy(id: reminder.id, weekdayPolicy: policy)
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                var updatedReminders = reminders
                updatedReminders[index].weekdayPolicy = policy
                reminders = updatedReminders
            }
            Haptics.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPaused(_ isPaused: Bool, for reminder: CityReminderGroup) async {
        guard beginUpdate(for: reminder.id, showsPauseProgress: true) else { return }
        defer { endUpdate(for: reminder.id) }

        do {
            try await reminderService.setReminderPaused(id: reminder.id, isPaused: isPaused)
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                var updatedReminders = reminders
                updatedReminders[index].isPaused = isPaused
                reminders = updatedReminders
            }
            Haptics.light()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isPauseUpdating(_ reminder: CityReminderGroup) -> Bool {
        pausingReminderIDs.contains(reminder.id)
    }

    func clearError() {
        errorMessage = nil
    }

    private func beginUpdate(for reminderID: String, showsPauseProgress: Bool) -> Bool {
        let inserted = updatingReminderIDs.insert(reminderID).inserted
        if inserted && showsPauseProgress {
            pausingReminderIDs.insert(reminderID)
        }
        return inserted
    }

    private func endUpdate(for reminderID: String) {
        updatingReminderIDs.remove(reminderID)
        pausingReminderIDs.remove(reminderID)
    }

    // MARK: - 城市信息查询

    private func loadCityCache() {
        do {
            let cities = try cityService.getAllCities()
            cityCache = Dictionary(uniqueKeysWithValues: cities.map { ($0.id, $0) })
        } catch {
            cityCache = [:]
        }
    }

    /// 根据 cityID 获取城市模型
    func city(for id: UUID) -> CityModel? {
        cityCache[id]
    }

    /// 城市国家码：优先取模型字段，旧数据为空时从内置城市目录补全
    func countryCode(for city: CityModel) -> String {
        if !city.country.isEmpty { return city.country }
        return CityService.countryCode(cityEn: city.cityEn, timezoneId: city.timezoneId)
    }

    /// 时差文案
    func timeDifference(for targetTimezoneId: String, localTimezoneId: String) -> String {
        timezoneService.getTimeDifferenceBetween(
            sourceTimezoneId: localTimezoneId,
            targetTimezoneId: targetTimezoneId
        ).offset
    }

    /// 夏令时状态
    func dstStatus(for timezoneId: String) -> String? {
        timezoneService.getDSTStatus(timezoneId: timezoneId)
    }
}
