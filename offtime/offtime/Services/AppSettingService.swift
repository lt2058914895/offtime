import Foundation

/// 设置服务兼容层：所有读写已迁移至 AppEnvironment + UserDefaults。
/// 保留此文件仅为过渡期兼容，新代码请直接使用 AppEnvironment.settings。
@available(*, deprecated, message: "请使用 AppEnvironment.settings 和 AppEnvironment.updateSettings()")
final class AppSettingService {
    static let shared = AppSettingService()
    private init() {}
    
    func loadSettings() throws -> AppSettings {
        let use24Hour = UserDefaults.standard.object(forKey: "settings_use24Hour") as? Bool
            ?? Locale.systemUses24Hour
        let themeRaw = UserDefaults.standard.integer(forKey: "settings_themeMode")
        let themeMode = ThemeMode(rawValue: themeRaw) ?? .system
        return AppSettings(use24Hour: use24Hour, themeMode: themeMode)
    }
    
    func saveSettings(_ settings: AppSettings) throws {
        UserDefaults.standard.set(settings.use24Hour, forKey: "settings_use24Hour")
        UserDefaults.standard.set(settings.themeMode.rawValue, forKey: "settings_themeMode")
    }
}