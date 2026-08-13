import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    @Published var themeMode: ThemeMode = AppSettings.defaults.themeMode
    
    @Published var errorMessage: String?
    
    init() {
        loadSettings()
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "app_settings"),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            use24Hour = settings.use24Hour
            themeMode = settings.themeMode
        }
    }
    
    private func saveSettings() {
        let settings = AppSettings(use24Hour: use24Hour, themeMode: themeMode)
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "app_settings")
        }
    }
    
    func toggle24Hour() {
        saveSettings()
    }
    
    func updateTheme(_ mode: ThemeMode) {
        themeMode = mode
        saveSettings()
    }
    
    func exportCities() -> Data? {
        do {
            return try CityService.shared.exportCities()
        } catch {
            errorMessage = String(localized: "settings.export.failed")
            return nil
        }
    }
    
    func importCities(from data: Data, strategy: ImportStrategy) -> Bool {
        do {
            try CityService.shared.importCities(from: data, strategy: strategy)
            return true
        } catch {
            errorMessage = String(localized: "settings.import.failed")
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
}