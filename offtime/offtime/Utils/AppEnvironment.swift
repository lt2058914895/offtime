import SwiftUI
import SwiftData
import Combine
import os

@MainActor
final class AppEnvironment: ObservableObject {
    @Published var settings: AppSettings = AppSettings.defaults
    
    /// SwiftData ModelContainer，App 启动时创建一次，全生命周期复用
    let modelContainer: ModelContainer
    
    /// 是否已完成首启引导（新用户为 false，老用户/已完成用户为 true）
    @Published var onboardingCompleted: Bool = false
    /// 城市数据版本号：导入/批量删除等改变城市列表的操作后递增，监听方据此刷新本地缓存
    @Published var citiesRevision: Int = 0

    private let logger = Logger(subsystem: "lt.offtime", category: "AppEnvironment")

    init() {
        do {
            let schema = Schema([CityModel.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // SwiftData 初始化失败时用空容器兜底，避免 App 崩溃；
            // 实际场景极少发生（iOS 17+ 系统框架保障）
            logger.error("SwiftData ModelContainer 创建失败: \(error.localizedDescription)")
            modelContainer = try! ModelContainer(for: Schema([CityModel.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
        // 立即注入 CityService，确保任何后续调用都能访问 ModelContext
        CityService.shared.modelContainer = modelContainer
    }

    /// App 启动后调用：首启种子城市、加载引导状态与设置
    func setup() {
        seedDefaultCityIfFirstLaunch()
        loadOnboardingState()
        loadSettings()
    }

    // MARK: - 首启种子城市

    /// 首次启动时根据设备系统时区自动加入一个默认城市，避免空列表。
    /// 幂等：通过 UserDefaults 标志位保证只执行一次。
    private func seedDefaultCityIfFirstLaunch() {
        let seededKey = "first_launch_seeded"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let context = modelContainer.mainContext
        var fetch = FetchDescriptor<CityModel>()
        fetch.fetchLimit = 1

        guard (try? context.fetch(fetch))?.isEmpty == true else {
            // 已有城市，标记已种子
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        let timezoneId = TimeZone.current.identifier
        let (cityName, cityEn) = CityService.matchCity(for: timezoneId)
        let city = CityModel(cityName: cityName, cityEn: cityEn, timezoneId: timezoneId, sortIndex: 0)
        context.insert(city)
        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    // MARK: - 引导状态

    private func loadOnboardingState() {
        onboardingCompleted = UserDefaults.standard.bool(forKey: "onboarding_completed")
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        onboardingCompleted = true
    }

    // MARK: - 设置

    func loadSettings() {
        let use24Hour = UserDefaults.standard.object(forKey: "settings_use24Hour") as? Bool
            ?? Locale.systemUses24Hour
        let themeRaw = UserDefaults.standard.integer(forKey: "settings_themeMode")
        let themeMode = ThemeMode(rawValue: themeRaw) ?? .system
        let localWorkStart = UserDefaults.standard.object(forKey: "settings_localWorkStart") as? Int ?? 9
        let localWorkEnd = UserDefaults.standard.object(forKey: "settings_localWorkEnd") as? Int ?? 18
        settings = AppSettings(use24Hour: use24Hour, themeMode: themeMode, localWorkStart: localWorkStart, localWorkEnd: localWorkEnd)
    }

    func updateSettings(_ newSettings: AppSettings) {
        UserDefaults.standard.set(newSettings.use24Hour, forKey: "settings_use24Hour")
        UserDefaults.standard.set(newSettings.themeMode.rawValue, forKey: "settings_themeMode")
        UserDefaults.standard.set(newSettings.localWorkStart, forKey: "settings_localWorkStart")
        UserDefaults.standard.set(newSettings.localWorkEnd, forKey: "settings_localWorkEnd")
        settings = newSettings
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
