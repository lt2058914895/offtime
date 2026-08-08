import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var use24Hour: Bool = Locale.systemUses24Hour
    @Published var themeMode: ThemeMode = .system
    
    @Published var errorMessage: String?
    
    private let appSettingService = AppSettingService.shared
    
    init() {
        loadSettings()
    }
    
    private func loadSettings() {
        Task {
            do {
                let settings = try appSettingService.loadSettings()
                await MainActor.run {
                    self.use24Hour = settings.use24Hour
                    self.themeMode = settings.themeMode
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = String(localized: "settings.load.failed")
                }
            }
        }
    }
    
    func toggle24Hour() {
        Task {
            do {
                try appSettingService.updateUse24Hour(use24Hour)
            } catch {
                await MainActor.run {
                    self.errorMessage = String(localized: "settings.save.failed")
                }
            }
        }
    }
    
    func updateTheme(_ mode: ThemeMode) {
        Task {
            do {
                try appSettingService.updateThemeMode(mode)
                await MainActor.run {
                    self.themeMode = mode
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = String(localized: "settings.save.theme.failed")
                }
            }
        }
    }
    
    func exportCities() -> Data? {
        do {
            return try CityService.shared.exportCities()
        } catch {
            errorMessage = String(localized: "settings.export.failed")
            return nil
        }
    }
    
    func importCities(from data: Data) -> Bool {
        do {
            try CityService.shared.importCities(from: data)
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
