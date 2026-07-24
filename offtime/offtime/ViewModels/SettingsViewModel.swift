import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var use24Hour: Bool = true
    @Published var themeMode: ThemeMode = .system
    @Published var tzDataVersion: String = "2024a"
    
    @Published var isCheckingUpdate: Bool = false
    @Published var updateMessage: String?
    
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
                    self.tzDataVersion = settings.localTzDataVersion
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载设置失败"
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
                    self.errorMessage = "保存设置失败"
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
                    self.errorMessage = "保存主题失败"
                }
            }
        }
    }
    
    func checkTzDataUpdate() {
        isCheckingUpdate = true
        updateMessage = nil
        
        Task {
            do {
                let version = await appSettingService.checkTzDataUpdate()
                await MainActor.run {
                    self.isCheckingUpdate = false
                    if version > self.tzDataVersion {
                        self.updateMessage = "发现新版本: \(version)"
                    } else {
                        self.updateMessage = "已是最新版本"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCheckingUpdate = false
                    self.updateMessage = "检查更新失败，请检查网络"
                }
            }
        }
    }
    
    func exportCities() -> Data? {
        do {
            return try CityService.shared.exportCities()
        } catch {
            errorMessage = "导出失败"
            return nil
        }
    }
    
    func importCities(from data: Data) -> Bool {
        do {
            try CityService.shared.importCities(from: data)
            return true
        } catch {
            errorMessage = "导入失败，文件格式错误"
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
    
    func dismissUpdateMessage() {
        updateMessage = nil
    }
}
