import SwiftUI
import Combine

final class AppEnvironment: ObservableObject {
    @Published var settings: AppSettings = AppSettings(
        use24Hour: true,
        themeMode: .system,
        localTzDataVersion: "2024a"
    )
    
    /// 数据库初始化状态：nil 表示未开始，true 表示成功，false 表示失败
    @Published var databaseReady: Bool? = nil
    @Published var databaseErrorMessage: String? = nil
    
    private let appSettingService = AppSettingService.shared
    
    func setupDatabase() {
        do {
            try DatabaseRepository.shared.setup()
            databaseReady = true
        } catch {
            databaseReady = false
            databaseErrorMessage = error.localizedDescription
        }
    }
    
    func loadSettings() {
        Task {
            do {
                let settings = try appSettingService.loadSettings()
                await MainActor.run {
                    self.settings = settings
                }
            } catch {
                // 使用默认设置
            }
        }
    }
    
    func updateSettings(_ newSettings: AppSettings) {
        Task {
            do {
                try appSettingService.saveSettings(newSettings)
                await MainActor.run {
                    self.settings = newSettings
                }
            } catch {
                // 保存失败，使用内存中的值
            }
        }
    }
    
    var colorScheme: ColorScheme? {
        switch settings.themeMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}