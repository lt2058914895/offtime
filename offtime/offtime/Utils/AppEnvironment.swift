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
        let schema = Schema([CityModel.self, MeetingModel.self])
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema 变更导致旧存储不兼容，删除旧存储文件后重建（一次性数据丢失）
            logger.error("SwiftData ModelContainer 创建失败，尝试删除旧存储: \(error.localizedDescription)")
            if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let storeURL = appSupport.appendingPathComponent("default.store")
                try? FileManager.default.removeItem(at: storeURL)
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("-wal"))
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("-shm"))
            }
            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: false)
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                // 重建仍失败，用内存容器兜底避免崩溃
                logger.error("SwiftData 重建仍失败，回退内存模式: \(error.localizedDescription)")
                modelContainer = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            }
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
        // 清理孤立通知提醒（城市已删除但通知仍残留）
        cleanupOrphanedReminders()
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

    /// 清理孤立通知提醒：城市已从列表删除但通知仍残留的情况（如卸载重装后 iOS 恢复旧通知）
    private func cleanupOrphanedReminders() {
        Task {
            let context = modelContainer.mainContext
            let fetch = FetchDescriptor<CityModel>()
            let cities = (try? context.fetch(fetch)) ?? []
            let validCityIDs = Set(cities.map { $0.id.uuidString })

            let reminderService = CityReminderService()
            let allReminders = await reminderService.allReminders()

            for reminder in allReminders {
                if !validCityIDs.contains(reminder.cityID.uuidString) {
                    await reminderService.removeReminder(id: reminder.id)
                }
            }
        }
    }

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
