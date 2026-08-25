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
    /// 全局分钟时钟：列表与详情页共享，避免每个 ViewModel 重复注册 RunLoop Timer
    @Published private(set) var currentDate = Date()

    private let logger = Logger(subsystem: "lt.offtime", category: "AppEnvironment")
    private var minuteTimer: Timer?

    init() {
        do {
            let schema = Schema([CityModel.self, MeetingModel.self, TripModel.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // SwiftData 初始化失败时用空容器兜底，避免 App 崩溃；
            // 实际场景极少发生（iOS 17+ 系统框架保障）
            logger.error("SwiftData ModelContainer 创建失败: \(error.localizedDescription)")
            modelContainer = try! ModelContainer(for: Schema([CityModel.self, MeetingModel.self, TripModel.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
        // 立即注入 CityService，确保任何后续调用都能访问 ModelContext
        CityService.shared.modelContainer = modelContainer
        // 首帧渲染前同步读取引导状态，避免非新用户进入 App 时引导页一闪而过
        loadOnboardingState()
    }

    /// App 启动后调用：首启种子城市、加载引导状态与设置
    func setup() {
        seedDefaultCityIfFirstLaunch()
        loadOnboardingState()
        loadSettings()
        // 旧版 UserDefaults 单草稿 → SwiftData 行程（一次性迁移）
        TripStore.shared.migrateLegacyDraftIfNeeded(context: modelContainer.mainContext)
    }

    // MARK: - 分钟时钟

    func startMinuteClock() {
        currentDate = Date()
        guard minuteTimer == nil else { return }

        let nextMinute = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(second: 0, nanosecond: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60)
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentDate = Date()
            }
        }
        timer.tolerance = 5
        timer.fireDate = nextMinute
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    func stopMinuteClock() {
        minuteTimer?.invalidate()
        minuteTimer = nil
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
        let currentCityTimezoneId = UserDefaults.standard.string(forKey: "settings_currentCityTimezoneId")
            ?? TimeZone.current.identifier
        let currentCityName = UserDefaults.standard.string(forKey: "settings_currentCityName")
        let currentCityEn = UserDefaults.standard.string(forKey: "settings_currentCityEn")
        settings = AppSettings(use24Hour: use24Hour, themeMode: themeMode, currentCityTimezoneId: currentCityTimezoneId, currentCityName: currentCityName, currentCityEn: currentCityEn)
        
        // 首次启动时，如果 currentCityName 为空，尝试从内置城市库匹配名称
        if settings.currentCityName == nil, let tzId = settings.currentCityTimezoneId {
            let (name, en) = CityService.matchCity(for: tzId)
            var s = settings
            s.currentCityName = name
            s.currentCityEn = en
            updateSettings(s)
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        UserDefaults.standard.set(newSettings.use24Hour, forKey: "settings_use24Hour")
        UserDefaults.standard.set(newSettings.themeMode.rawValue, forKey: "settings_themeMode")
        UserDefaults.standard.set(newSettings.currentCityTimezoneId, forKey: "settings_currentCityTimezoneId")
        if let name = newSettings.currentCityName {
            UserDefaults.standard.set(name, forKey: "settings_currentCityName")
        } else {
            UserDefaults.standard.removeObject(forKey: "settings_currentCityName")
        }
        if let en = newSettings.currentCityEn {
            UserDefaults.standard.set(en, forKey: "settings_currentCityEn")
        } else {
            UserDefaults.standard.removeObject(forKey: "settings_currentCityEn")
        }
        settings = newSettings
    }

    /// 切换当前城市：从城市库选择后更新时区、名称（工作时间由各城市详情页独立维护）
    func switchCurrentCity(_ city: CitySuggestion) {
        var newSettings = settings
        newSettings.currentCityTimezoneId = city.timezoneId
        newSettings.currentCityName = city.cityName
        newSettings.currentCityEn = city.cityEn
        updateSettings(newSettings)
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
