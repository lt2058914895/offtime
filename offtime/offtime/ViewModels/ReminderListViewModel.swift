import SwiftUI
import Combine

@MainActor
final class ReminderListViewModel: ObservableObject {
    @Published var reminders: [CityReminderGroup] = []
    @Published var isLoading = false

    private let reminderService: CityReminderService
    private let cityService = CityService.shared
    private let timezoneService = TimezoneService.shared

    /// 城市 ID → CityModel 缓存，用于 section header 展示国旗、国家、UTC、时差、DST
    private var cityCache: [UUID: CityModel] = [:]

    /// 内置城市目录缓存：英文名+时区 → 国家码
    private static let countryCatalog: [String: String] = {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cities = try? JSONDecoder().decode([CitySuggestion].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: cities.map {
            ("\($0.cityEn)|\($0.timezoneId)", $0.country)
        })
    }()

    init(reminderService: CityReminderService? = nil) {
        self.reminderService = reminderService ?? CityReminderService(
            modelContainer: CityService.shared.modelContainer
        )
    }

    func loadReminders() async {
        isLoading = true
        reminders = await reminderService.allReminders()
        loadCityCache()
        isLoading = false
    }

    func deleteReminder(_ reminder: CityReminderGroup) async {
        await reminderService.removeReminder(id: reminder.id)
        reminders.removeAll { $0.id == reminder.id }
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
        return Self.countryCatalog["\(city.cityEn)|\(city.timezoneId)"] ?? ""
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
