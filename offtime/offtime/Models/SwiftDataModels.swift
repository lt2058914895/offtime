import Foundation
import SwiftData

/// SwiftData 持久化模型：用户添加的城市时钟
@Model
final class CityModel {
    var id: UUID
    var cityName: String
    var cityEn: String
    var timezoneId: String
    var country: String = ""
    var sortIndex: Int
    /// 旧版整点字段：保留写入，供旧版本回退读取；新逻辑只读取分钟字段。
    var workStartHour: Int = 9
    var workEndHour: Int = 18
    var localWorkStart: Int = 9
    var localWorkEnd: Int = 18
    /// 分钟制工作时段（距离当天 00:00 的分钟数）。为兼容旧库，缺失时回退到整点字段。
    var workStartMinutes: Int?
    var workEndMinutes: Int?
    var localWorkStartMinutes: Int?
    var localWorkEndMinutes: Int?
    
    init(
        id: UUID = UUID(),
        cityName: String,
        cityEn: String,
        timezoneId: String,
        country: String = "",
        sortIndex: Int = 0,
        workStartHour: Int = 9,
        workEndHour: Int = 18,
        localWorkStart: Int = 9,
        localWorkEnd: Int = 18,
        workStartMinutes: Int? = nil,
        workEndMinutes: Int? = nil,
        localWorkStartMinutes: Int? = nil,
        localWorkEndMinutes: Int? = nil
    ) {
        let targetHours = MinuteTime.sanitizedWorkHours(
            startMinutes: workStartMinutes ?? workStartHour * MinuteTime.minutesPerHour,
            endMinutes: workEndMinutes ?? workEndHour * MinuteTime.minutesPerHour
        )
        let currentHours = MinuteTime.sanitizedWorkHours(
            startMinutes: localWorkStartMinutes ?? localWorkStart * MinuteTime.minutesPerHour,
            endMinutes: localWorkEndMinutes ?? localWorkEnd * MinuteTime.minutesPerHour
        )

        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.country = country
        self.sortIndex = sortIndex
        self.workStartHour = MinuteTime.hour(of: targetHours.start)
        self.workEndHour = MinuteTime.hour(of: targetHours.end)
        self.localWorkStart = MinuteTime.hour(of: currentHours.start)
        self.localWorkEnd = MinuteTime.hour(of: currentHours.end)
        self.workStartMinutes = targetHours.start
        self.workEndMinutes = targetHours.end
        self.localWorkStartMinutes = currentHours.start
        self.localWorkEndMinutes = currentHours.end
    }
}

// MARK: - CityModel ↔ CityItem 转换

extension CityModel {
    /// 转为轻量值类型，用于导出、分享等不需要 SwiftData 上下文的场景
    func toItem() -> CityItem {
        let targetHours = workHours
        let currentHours = localWorkHours
        return CityItem(
            id: id,
            cityName: cityName,
            cityEn: cityEn,
            timezoneId: timezoneId,
            country: country,
            sortIndex: sortIndex,
            workHours: targetHours,
            localWorkHours: currentHours
        )
    }

    /// 目标城市工作时段。分钟字段缺失时（旧版本数据）回退到整点字段。
    var workHours: WorkHours {
        let fallbackStart = workStartHour * MinuteTime.minutesPerHour
        let fallbackEnd = workEndHour * MinuteTime.minutesPerHour
        return WorkHours(
            startMinutes: workStartMinutes ?? fallbackStart,
            endMinutes: workEndMinutes ?? fallbackEnd
        ).sanitized()
    }

    /// 当前城市工作时段。分钟字段缺失时（旧版本数据）回退到整点字段。
    var localWorkHours: WorkHours {
        let fallbackStart = localWorkStart * MinuteTime.minutesPerHour
        let fallbackEnd = localWorkEnd * MinuteTime.minutesPerHour
        return WorkHours(
            startMinutes: localWorkStartMinutes ?? fallbackStart,
            endMinutes: localWorkEndMinutes ?? fallbackEnd
        ).sanitized()
    }

    func updateWorkHours(_ hours: WorkHours) {
        let sanitized = hours.sanitized()
        workStartMinutes = sanitized.startMinutes
        workEndMinutes = sanitized.endMinutes
        workStartHour = MinuteTime.hour(of: sanitized.startMinutes)
        workEndHour = MinuteTime.hour(of: sanitized.endMinutes)
    }

    func updateLocalWorkHours(_ hours: WorkHours) {
        let sanitized = hours.sanitized()
        localWorkStartMinutes = sanitized.startMinutes
        localWorkEndMinutes = sanitized.endMinutes
        localWorkStart = MinuteTime.hour(of: sanitized.startMinutes)
        localWorkEnd = MinuteTime.hour(of: sanitized.endMinutes)
    }

    /// 把旧数据中的整点字段补写成分钟字段。返回是否发生了修改。
    @discardableResult
    func migrateLegacyWorkHoursIfNeeded() -> Bool {
        let targetHours = workHours
        let currentHours = localWorkHours
        guard workStartMinutes == nil
            || workEndMinutes == nil
            || localWorkStartMinutes == nil
            || localWorkEndMinutes == nil else {
            return false
        }

        updateWorkHours(targetHours)
        updateLocalWorkHours(currentHours)
        return true
    }
}

// MARK: - 已添加的会议

/// SwiftData 持久化模型：用户从推荐档期加入的会议
@Model
final class MeetingModel {
    var id: UUID
    var startDate: Date
    var durationMinutes: Int
    var localTimezoneId: String
    var participantNames: [String]
    var participantEnNames: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        durationMinutes: Int,
        localTimezoneId: String,
        participantNames: [String],
        participantEnNames: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.localTimezoneId = localTimezoneId
        self.participantNames = participantNames
        self.participantEnNames = participantEnNames
        self.createdAt = createdAt
    }
}

// MARK: - 城市提醒

/// 提醒在哪些城市的“工作日”触发。这里的工作日固定为周一至周五。
enum CityReminderWeekdayPolicy: String, CaseIterable, Codable, Identifiable {
    case everyDay
    case bothCities
    case currentCity
    case targetCity

    var id: String { rawValue }

    var requiresWeekdayFiltering: Bool {
        self != .everyDay
    }

    var includesCurrentCity: Bool {
        self == .bothCities || self == .currentCity
    }

    var includesTargetCity: Bool {
        self == .bothCities || self == .targetCity
    }

    var legacyWeekdaysOnly: Bool {
        requiresWeekdayFiltering
    }

    init(legacyWeekdaysOnly: Bool) {
        self = legacyWeekdaysOnly ? .bothCities : .everyDay
    }
}

/// SwiftData 持久化模型：城市可联系时段提醒。
/// 通知中心是调度通道，这里才是提醒列表和启动补偿的事实来源。
@Model
final class ReminderModel {
    var id: UUID
    var cityID: UUID
    var cityName: String
    var timezoneId: String
    var hour: Int
    var minute: Int
    /// 兼容旧版本数据；新版本使用 weekdayPolicyRaw 区分四种重复规则。
    var weekdaysOnly: Bool
    var weekdayPolicyRaw: String?
    var targetTimezoneId: String
    var targetHour: Int
    var targetMinute: Int
    var isPaused: Bool = false
    var triggerCityName: String?
    var triggerCityEn: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        cityID: UUID,
        cityName: String,
        timezoneId: String,
        hour: Int,
        minute: Int,
        weekdayPolicy: CityReminderWeekdayPolicy,
        targetTimezoneId: String,
        targetHour: Int,
        targetMinute: Int,
        isPaused: Bool = false,
        triggerCityName: String? = nil,
        triggerCityEn: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cityID = cityID
        self.cityName = cityName
        self.timezoneId = timezoneId
        self.hour = hour
        self.minute = minute
        self.weekdaysOnly = weekdayPolicy.legacyWeekdaysOnly
        self.weekdayPolicyRaw = weekdayPolicy.rawValue
        self.targetTimezoneId = targetTimezoneId
        self.targetHour = targetHour
        self.targetMinute = targetMinute
        self.isPaused = isPaused
        self.triggerCityName = triggerCityName
        self.triggerCityEn = triggerCityEn
        self.createdAt = createdAt
    }
}

extension ReminderModel {
    /// 旧数据没有 weekdayPolicyRaw 时，根据原来的 Bool 安全回退。
    var weekdayPolicy: CityReminderWeekdayPolicy {
        weekdayPolicyRaw.flatMap(CityReminderWeekdayPolicy.init(rawValue:))
            ?? CityReminderWeekdayPolicy(legacyWeekdaysOnly: weekdaysOnly)
    }

    func toGroup() -> CityReminderGroup {
        CityReminderGroup(
            id: id.uuidString,
            cityID: cityID,
            cityName: cityName,
            timezoneId: timezoneId,
            hour: hour,
            minute: minute,
            weekdayPolicy: weekdayPolicy,
            targetTimezoneId: targetTimezoneId,
            targetHour: targetHour,
            targetMinute: targetMinute,
            isPaused: isPaused,
            triggerCityName: triggerCityName,
            triggerCityEn: triggerCityEn
        )
    }
}

// MARK: - CityItem 保留为 Codable 值类型，仅用于导入/导出 JSON 兼容

/// 城市值类型，用于 JSON 导入/导出。运行时数据操作请使用 CityModel。
struct CityItem: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    let cityName: String
    let cityEn: String
    let timezoneId: String
    let country: String
    var sortIndex: Int
    /// 分钟制工作时段（距离当天 00:00 的分钟数）。
    var workStartMinutes: Int
    var workEndMinutes: Int
    var localWorkStartMinutes: Int
    var localWorkEndMinutes: Int

    var workStartHour: Int { MinuteTime.hour(of: workStartMinutes) }
    var workEndHour: Int { MinuteTime.hour(of: workEndMinutes) }
    var localWorkStart: Int { MinuteTime.hour(of: localWorkStartMinutes) }
    var localWorkEnd: Int { MinuteTime.hour(of: localWorkEndMinutes) }

    var workHours: WorkHours {
        WorkHours(startMinutes: workStartMinutes, endMinutes: workEndMinutes)
    }

    var localWorkHours: WorkHours {
        WorkHours(startMinutes: localWorkStartMinutes, endMinutes: localWorkEndMinutes)
    }

    /// 兼容旧版按整点调用构造的入口；内部仍写入分钟字段。
    init(
        id: UUID,
        cityName: String,
        cityEn: String,
        timezoneId: String,
        country: String = "",
        sortIndex: Int,
        workStartHour: Int = 9,
        workEndHour: Int = 18,
        localWorkStart: Int = 9,
        localWorkEnd: Int = 18
    ) {
        let targetHours = MinuteTime.sanitizedWorkHours(
            startMinutes: workStartHour * MinuteTime.minutesPerHour,
            endMinutes: workEndHour * MinuteTime.minutesPerHour
        )
        let currentHours = MinuteTime.sanitizedWorkHours(
            startMinutes: localWorkStart * MinuteTime.minutesPerHour,
            endMinutes: localWorkEnd * MinuteTime.minutesPerHour
        )
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.country = country
        self.sortIndex = sortIndex
        self.workStartMinutes = targetHours.start
        self.workEndMinutes = targetHours.end
        self.localWorkStartMinutes = currentHours.start
        self.localWorkEndMinutes = currentHours.end
    }

    /// 分钟制入口。可联系时段和提醒全部使用这条路径。
    init(
        id: UUID,
        cityName: String,
        cityEn: String,
        timezoneId: String,
        country: String = "",
        sortIndex: Int,
        workHours: WorkHours,
        localWorkHours: WorkHours
    ) {
        let targetHours = workHours.sanitized()
        let currentHours = localWorkHours.sanitized()
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.country = country
        self.sortIndex = sortIndex
        self.workStartMinutes = targetHours.startMinutes
        self.workEndMinutes = targetHours.endMinutes
        self.localWorkStartMinutes = currentHours.startMinutes
        self.localWorkEndMinutes = currentHours.endMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        cityName = try c.decode(String.self, forKey: .cityName)
        cityEn = try c.decode(String.self, forKey: .cityEn)
        timezoneId = try c.decode(String.self, forKey: .timezoneId)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        sortIndex = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
        let legacyWorkStartHour = try c.decodeIfPresent(Int.self, forKey: .workStartHour) ?? 9
        let legacyWorkEndHour = try c.decodeIfPresent(Int.self, forKey: .workEndHour) ?? 18
        let legacyLocalWorkStart = try c.decodeIfPresent(Int.self, forKey: .localWorkStart) ?? 9
        let legacyLocalWorkEnd = try c.decodeIfPresent(Int.self, forKey: .localWorkEnd) ?? 18
        workStartMinutes = try c.decodeIfPresent(Int.self, forKey: .workStartMinutes)
            ?? legacyWorkStartHour * MinuteTime.minutesPerHour
        workEndMinutes = try c.decodeIfPresent(Int.self, forKey: .workEndMinutes)
            ?? legacyWorkEndHour * MinuteTime.minutesPerHour
        localWorkStartMinutes = try c.decodeIfPresent(Int.self, forKey: .localWorkStartMinutes)
            ?? legacyLocalWorkStart * MinuteTime.minutesPerHour
        localWorkEndMinutes = try c.decodeIfPresent(Int.self, forKey: .localWorkEndMinutes)
            ?? legacyLocalWorkEnd * MinuteTime.minutesPerHour
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(cityName, forKey: .cityName)
        try c.encode(cityEn, forKey: .cityEn)
        try c.encode(timezoneId, forKey: .timezoneId)
        try c.encode(country, forKey: .country)
        try c.encode(sortIndex, forKey: .sortIndex)
        try c.encode(workStartMinutes, forKey: .workStartMinutes)
        try c.encode(workEndMinutes, forKey: .workEndMinutes)
        try c.encode(localWorkStartMinutes, forKey: .localWorkStartMinutes)
        try c.encode(localWorkEndMinutes, forKey: .localWorkEndMinutes)
        // 同时写出旧整点字段：新版本读取分钟字段，旧版本仍可读取自己认识的字段。
        try c.encode(workStartHour, forKey: .workStartHour)
        try c.encode(workEndHour, forKey: .workEndHour)
        try c.encode(localWorkStart, forKey: .localWorkStart)
        try c.encode(localWorkEnd, forKey: .localWorkEnd)
    }

    private enum CodingKeys: String, CodingKey {
        case id, cityName, cityEn, timezoneId, country, sortIndex
        case workStartMinutes, workEndMinutes, localWorkStartMinutes, localWorkEndMinutes
        case workStartHour, workEndHour, localWorkStart, localWorkEnd
    }
}

// MARK: - 导入/导出信封

/// 导出文件信封：带 schemaVersion，便于未来字段变更时做兼容判断。
struct CitiesExportEnvelope: Codable {
    static let currentSchemaVersion = 3
    static let minimumSupportedSchemaVersion = 1
    var schemaVersion: Int
    var cities: [CityItem]
}

// MARK: - 其他值类型（与 SwiftData 无关，保持不变）

enum ViewState: Equatable {
    case idle
    case loading
    case failure(String)
}

struct AppSettings: Equatable, Codable {
    var use24Hour: Bool
    var themeMode: ThemeMode
    var widgetCustomTheme: ThemeStyleConfiguration
    var currentCityTimezoneId: String?
    var currentCityName: String?
    var currentCityEn: String?
}

extension AppSettings {
    static let defaults = AppSettings(
        use24Hour: Locale.systemUses24Hour,
        themeMode: .system,
        widgetCustomTheme: .default,
        currentCityTimezoneId: TimeZone.current.identifier,
        currentCityName: nil,
        currentCityEn: nil
    )
}

enum ThemeMode: Int, Equatable, CaseIterable, Codable, Identifiable {
    var id: Int { rawValue }
    case system = 0
    case light = 1
    case dark = 2

    var displayName: String {
        switch self {
        case .system: return String(localized: "theme.system")
        case .light: return String(localized: "theme.light")
        case .dark: return String(localized: "theme.dark")
        }
    }
}

enum AppTab: Hashable {
    case clock
    case converter
    case settings
}

enum AppRoute: Hashable {
    case cityPicker
    case citySelector
    case addWidgetGuide
    case contactPage
    case meetingRecommendation
    case customTheme
    case reminderSound
    case cityDetail(UUID)
    case reminderList
}

struct CitySuggestion: Equatable, Identifiable, Codable {
    let id: String
    let cityName: String
    let cityEn: String
    let timezoneId: String
    let country: String
    let continent: String

    init(
        id: String,
        cityName: String,
        cityEn: String,
        timezoneId: String,
        country: String,
        continent: String
    ) {
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.country = country
        self.continent = continent
    }

    enum CodingKeys: String, CodingKey {
        case id, cityName, cityEn, timezoneId, country, continent
    }

    /// 兼容旧数据：country 是后新增字段，旧数据中缺失时回退为空字符串，
    /// 避免整体解码失败导致卡片空白。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cityName = try container.decode(String.self, forKey: .cityName)
        cityEn = try container.decode(String.self, forKey: .cityEn)
        timezoneId = try container.decode(String.self, forKey: .timezoneId)
        country = try container.decodeIfPresent(String.self, forKey: .country) ?? ""
        continent = try container.decode(String.self, forKey: .continent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(cityName, forKey: .cityName)
        try container.encode(cityEn, forKey: .cityEn)
        try container.encode(timezoneId, forKey: .timezoneId)
        try container.encode(country, forKey: .country)
        try container.encode(continent, forKey: .continent)
    }
}

struct CountryGroup: Equatable, Identifiable {
    let code: String
    let name: String
    let indexLetter: String
    let cities: [CitySuggestion]
    var id: String { code }
}

enum ImportStrategy {
    case merge
    case replace
}
