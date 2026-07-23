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
    var localTzDataVersion: String
}

enum ThemeMode: Int, Equatable, CaseIterable, Codable, Identifiable {
    var id: Int { rawValue }
    case system = 0
    case light = 1
    case dark = 2
    
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum AppRoute: Hashable {
    case cityPicker
    case citySelector
    case privacyPage
    case aboutPage
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
