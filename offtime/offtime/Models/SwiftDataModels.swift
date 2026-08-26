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
    var workStartHour: Int = 9
    var workEndHour: Int = 18
    var localWorkStart: Int = 9
    var localWorkEnd: Int = 18
    
    init(id: UUID = UUID(), cityName: String, cityEn: String, timezoneId: String, country: String = "", sortIndex: Int = 0, workStartHour: Int = 9, workEndHour: Int = 18, localWorkStart: Int = 9, localWorkEnd: Int = 18) {
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.country = country
        self.sortIndex = sortIndex
        self.workStartHour = workStartHour
        self.workEndHour = workEndHour
        self.localWorkStart = localWorkStart
        self.localWorkEnd = localWorkEnd
    }
}

// MARK: - CityModel ↔ CityItem 转换

extension CityModel {
    /// 转为轻量值类型，用于导出、分享等不需要 SwiftData 上下文的场景
    func toItem() -> CityItem {
        CityItem(
            id: id,
            cityName: cityName,
            cityEn: cityEn,
            timezoneId: timezoneId,
            country: country,
            sortIndex: sortIndex,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            localWorkStart: localWorkStart,
            localWorkEnd: localWorkEnd
        )
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
    var createdAt: Date

    init(
        id: UUID = UUID(),
        startDate: Date,
        durationMinutes: Int,
        localTimezoneId: String,
        participantNames: [String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.localTimezoneId = localTimezoneId
        self.participantNames = participantNames
        self.createdAt = createdAt
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
    var workStartHour: Int
    var workEndHour: Int
    var localWorkStart: Int
    var localWorkEnd: Int

    init(id: UUID, cityName: String, cityEn: String, timezoneId: String, country: String = "", sortIndex: Int, workStartHour: Int = 9, workEndHour: Int = 18, localWorkStart: Int = 9, localWorkEnd: Int = 18) {
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.country = country
        self.sortIndex = sortIndex
        self.workStartHour = workStartHour
        self.workEndHour = workEndHour
        self.localWorkStart = localWorkStart
        self.localWorkEnd = localWorkEnd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        cityName = try c.decode(String.self, forKey: .cityName)
        cityEn = try c.decode(String.self, forKey: .cityEn)
        timezoneId = try c.decode(String.self, forKey: .timezoneId)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        sortIndex = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
        workStartHour = try c.decodeIfPresent(Int.self, forKey: .workStartHour) ?? 9
        workEndHour = try c.decodeIfPresent(Int.self, forKey: .workEndHour) ?? 18
        localWorkStart = try c.decodeIfPresent(Int.self, forKey: .localWorkStart) ?? 9
        localWorkEnd = try c.decodeIfPresent(Int.self, forKey: .localWorkEnd) ?? 18
    }
}

// MARK: - 导入/导出信封

/// 导出文件信封：带 schemaVersion，便于未来字段变更时做兼容判断。
struct CitiesExportEnvelope: Codable {
    static let currentSchemaVersion = 2
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
    var currentCityTimezoneId: String?
    var currentCityName: String?
    var currentCityEn: String?
}

extension AppSettings {
    static let defaults = AppSettings(
        use24Hour: Locale.systemUses24Hour,
        themeMode: .system,
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
    case meeting
    case travel
    case settings
}

enum AppRoute: Hashable {
    case cityPicker
    case citySelector
    case supportPage
    case cityDetail(UUID)
}

struct TimezoneInfo: Equatable {
    let id: String
    let name: String
    let offset: TimeInterval
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

    /// 兼容旧数据：country 是后新增字段，旧行程 legsData 中缺失时回退为空字符串，
    /// 避免整体解码失败导致行程卡片空白。
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
