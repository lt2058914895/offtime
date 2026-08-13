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

    /// App 启动后调用：执行数据迁移、首启种子城市、判断引导状态
    func setup() {
        migrateFromSQLiteIfNeeded()
        seedDefaultCityIfFirstLaunch()
        loadOnboardingState()
        loadSettings()
    }

    // MARK: - SQLite → SwiftData 迁移

    /// 检测旧 SQLite 数据库文件，如有则读取数据写入 SwiftData，完成后删除旧文件。
    /// 幂等：通过 UserDefaults 标志位保证只执行一次。
    private func migrateFromSQLiteIfNeeded() {
        let migratedKey = "sqlite_migrated_to_swiftdata"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }

        let dbURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("offtime.sqlite")

        guard let url = dbURL, FileManager.default.fileExists(atPath: url.path) else {
            // 无旧数据库，标记已迁移
            UserDefaults.standard.set(true, forKey: migratedKey)
            return
        }

        logger.info("检测到旧 SQLite 数据库，开始迁移至 SwiftData...")

        // 使用旧 DatabaseRepository 读取数据
        do {
            try DatabaseRepository.shared.setup()
            let records = try DatabaseRepository.shared.getAllCities()

            let context = modelContainer.mainContext
            for record in records {
                let model = CityModel(
                    id: UUID(uuidString: record.id) ?? UUID(),
                    cityName: record.cityName,
                    cityEn: record.cityEn,
                    timezoneId: record.timezoneId,
                    sortIndex: record.sortIndex
                )
                context.insert(model)
            }
            try context.save()

            // 迁移 onboarding 状态
            if let onboardingFlag = try? DatabaseRepository.shared.getConfig(key: "onboarding_completed"), onboardingFlag == "1" {
                UserDefaults.standard.set(true, forKey: "onboarding_completed")
            }

            // 迁移设置
            if let settingsJson = try? DatabaseRepository.shared.getConfig(key: "app_settings"),
               let data = settingsJson.data(using: .utf8),
               let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                UserDefaults.standard.set(settings.use24Hour, forKey: "settings_use24Hour")
                UserDefaults.standard.set(settings.themeMode.rawValue, forKey: "settings_themeMode")
            }

            // 迁移首启标志
            if let seededFlag = try? DatabaseRepository.shared.getConfig(key: "first_launch_seeded"), seededFlag == "1" {
                UserDefaults.standard.set(true, forKey: "first_launch_seeded")
            }

            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.set(true, forKey: migratedKey)
            logger.info("SQLite → SwiftData 迁移完成，已迁移 \(records.count) 个城市")
        } catch {
            logger.error("SQLite 迁移失败: \(error.localizedDescription)，保留旧数据库")
        }
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
        settings = AppSettings(use24Hour: use24Hour, themeMode: themeMode)
    }

    func updateSettings(_ newSettings: AppSettings) {
        UserDefaults.standard.set(newSettings.use24Hour, forKey: "settings_use24Hour")
        UserDefaults.standard.set(newSettings.themeMode.rawValue, forKey: "settings_themeMode")
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