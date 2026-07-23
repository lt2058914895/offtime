import Foundation

final class AppSettingService {
    static let shared = AppSettingService()
    
    private let repository = DatabaseRepository.shared
    private let configKey = "app_settings"
    
    private init() {}
    
    private let defaultSettings = AppSettings(
        use24Hour: true,
        themeMode: .system,
        localTzDataVersion: "2024a"
    )
    
    func loadSettings() throws -> AppSettings {
        if let json = try repository.getConfig(key: configKey) {
            if let data = json.data(using: .utf8) {
                let decoder = JSONDecoder()
                return try decoder.decode(AppSettings.self, from: data)
            }
        }
        return defaultSettings
    }
    
    func saveSettings(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        if let json = String(data: data, encoding: .utf8) {
            try repository.saveConfig(key: configKey, value: json)
        }
    }
    
    func updateUse24Hour(_ value: Bool) throws {
        var settings = try loadSettings()
        settings.use24Hour = value
        try saveSettings(settings)
    }
    
    func updateThemeMode(_ mode: ThemeMode) throws {
        var settings = try loadSettings()
        settings.themeMode = mode
        try saveSettings(settings)
    }
    
    func updateTzDataVersion(_ version: String) throws {
        var settings = try loadSettings()
        settings.localTzDataVersion = version
        try saveSettings(settings)
    }
    
    func checkTzDataUpdate(completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("2024a"))
    }
    
    func downloadTzData(completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.success(Data()))
    }
}
