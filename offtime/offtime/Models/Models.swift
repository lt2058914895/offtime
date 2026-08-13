import Foundation

enum ViewState: Equatable {
    case idle
    case loading
    case failure(String)
}

struct CityItem: Identifiable, Equatable, Codable, Hashable {
    let id: UUID
    let cityName: String
    let cityEn: String
    let timezoneId: String
    var sortIndex: Int
    var isTop: Bool
}

struct AppSettings: Equatable, Codable {
    var use24Hour: Bool
    var themeMode: ThemeMode
}

extension AppSettings {
    /// 全局默认设置：use24Hour 跟随系统 locale（"j" 模板推断），themeMode 跟随系统。
    /// 集中此处避免散落在各 ViewModel / Service 中漂移。
    static let defaults = AppSettings(
        use24Hour: Locale.systemUses24Hour,
        themeMode: .system
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

/// 底层 Tab 标识，用于 TabView selection 绑定，驱动「仅时钟 Tab 运行 Timer」等逻辑
enum AppTab: Hashable {
    case clock
    case converter
    case settings
}

enum AppRoute: Hashable {
    case cityPicker
    case citySelector
    case supportPage
}

struct CityRecord: Codable {
    var id: String
    var cityName: String
    var cityEn: String
    var timezoneId: String
    var sortIndex: Int
    var isTop: Int
}

struct AppConfigRecord: Codable {
    var key: String
    var value: String
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
