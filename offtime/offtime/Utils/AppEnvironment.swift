import SwiftUI
import Combine
import os

final class AppEnvironment: ObservableObject {
    @Published var settings: AppSettings = AppSettings.defaults
    
    /// 数据库初始化状态：nil 表示未开始，true 表示成功，false 表示失败
    @Published var databaseReady: Bool? = nil
    @Published var databaseErrorMessage: String? = nil
    /// 是否已完成首启引导（新用户为 false，老用户/已完成用户为 true）
    @Published var onboardingCompleted: Bool = false
    /// 城市数据版本号：导入/批量删除等改变城市列表的操作后递增，监听方据此刷新本地缓存
    @Published var citiesRevision: Int = 0

    private let appSettingService = AppSettingService.shared
    private let logger = Logger(subsystem: "lt.offtime", category: "AppEnvironment")

    func setupDatabase() {
        do {
            try DatabaseRepository.shared.setup()
            // 首启依据设备系统时区自动加入默认城市；返回是否为首次启动
            let isFirstLaunch = (try? CityService.shared.seedDefaultCityIfFirstLaunch()) ?? false
            // 老用户（非首次启动）直接跳过引导；新用户显示引导直至完成
            onboardingCompleted = !isFirstLaunch || appSettingService.isOnboardingCompleted()
            databaseReady = true
        } catch {
            databaseReady = false
            databaseErrorMessage = error.localizedDescription
        }
    }

    func completeOnboarding() {
        appSettingService.setOnboardingCompleted()
        onboardingCompleted = true
    }
    
    func loadSettings() {
        Task {
            do {
                let settings = try appSettingService.loadSettings()
                await MainActor.run {
                    self.settings = settings
                }
            } catch {
                logger.error("加载设置失败，使用默认设置: \(error.localizedDescription)")
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
                logger.error("保存设置失败，保留内存值: \(error.localizedDescription)")
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