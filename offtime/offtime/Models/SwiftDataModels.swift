import Foundation
import SwiftData

/// SwiftData 持久化模型：用户添加的城市时钟
@Model
final class CityModel {
    var id: UUID
    var cityName: String
    var cityEn: String
    var timezoneId: String
    var sortIndex: Int
    var workStartHour: Int = 9
    var workEndHour: Int = 18
    var localWorkStart: Int = 9
    var localWorkEnd: Int = 18
    
    init(id: UUID = UUID(), cityName: String, cityEn: String, timezoneId: String, sortIndex: Int = 0, workStartHour: Int = 9, workEndHour: Int = 18, localWorkStart: Int = 9, localWorkEnd: Int = 18) {
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
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
            sortIndex: sortIndex,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            localWorkStart: localWorkStart,
            localWorkEnd: localWorkEnd
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
    var sortIndex: Int
    var workStartHour: Int
    var workEndHour: Int
    var localWorkStart: Int
    var localWorkEnd: Int

    init(id: UUID, cityName: String, cityEn: String, timezoneId: String, sortIndex: Int, workStartHour: Int = 9, workEndHour: Int = 18, localWorkStart: Int = 9, localWorkEnd: Int = 18) {
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
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
    let continent: String
}

struct ContinentGroup: Equatable {
    let name: String
    let cities: [CitySuggestion]
}

enum ImportStrategy {
    case merge
    case replace
}
