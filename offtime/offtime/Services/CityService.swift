import Foundation
import SwiftData

extension Notification.Name {
    static let cityStoreDidChange = Notification.Name("lt.offtime.cityStoreDidChange")
}

@MainActor
final class CityService {
    static let shared = CityService()
    
    private init() {}
    
    // MARK: - ModelContext 获取
    
    /// 由 AppEnvironment 在启动时注入；容器创建失败时保持 nil。
    private(set) var modelContainer: ModelContainer?

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        migrateLegacyWorkHoursIfNeeded()
    }

    /// 旧版本只保存整点工作时段。启动时把整点值补写成分钟字段，
    /// 后续所有可联系计算都只读取分钟字段；旧字段仍同步写入以支持版本回退。
    func migrateLegacyWorkHoursIfNeeded() {
        guard let modelContainer else { return }
        let context = modelContainer.mainContext
        guard let cities = try? context.fetch(FetchDescriptor<CityModel>()) else { return }

        var didChange = false
        for city in cities where city.migrateLegacyWorkHoursIfNeeded() {
            didChange = true
        }
        if didChange {
            try? context.save()
        }
    }

    private func requireMainContext() throws -> ModelContext {
        guard let modelContainer else {
            throw CityError.storeUnavailable
        }
        return modelContainer.mainContext
    }

    private func resolveContext(_ context: ModelContext?) throws -> ModelContext {
        if let context {
            return context
        }
        return try requireMainContext()
    }
    
    // MARK: - City CRUD
    
    func addCity(cityName: String, cityEn: String, timezoneId: String, country: String = "", context: ModelContext? = nil) throws {
        let ctx = try resolveContext(context)

        // 判重：规范化英文名 + 时区 联合唯一（中文名不参与，避免同名不同城误判）
        if try findExisting(cityEn: cityEn, timezoneId: timezoneId, context: ctx) != nil {
            throw CityError.alreadyExists
        }
        
        let maxSortIndex = try getMaxSortIndex(context: ctx)
        let city = CityModel(
            cityName: cityName,
            cityEn: cityEn,
            timezoneId: timezoneId,
            country: country,
            sortIndex: maxSortIndex + 1
        )
        ctx.insert(city)
        try ctx.save()
        notifyCityStoreDidChange()
    }

    /// 按身份键查找已添加城市：先按 IANA 时区过滤，再在内存中比对规范化英文名。
    private func findExisting(cityEn: String, timezoneId: String, context: ModelContext) throws -> CityModel? {
        let key = CityIdentity.key(cityEn: cityEn, timezoneId: timezoneId)
        let fetch = FetchDescriptor<CityModel>(
            predicate: #Predicate { $0.timezoneId == timezoneId }
        )
        let candidates = try context.fetch(fetch)
        return candidates.first {
            CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId) == key
        }
    }
    
    func deleteCity(id: UUID, context: ModelContext? = nil) throws {
        let ctx = try resolveContext(context)
        let idToFind = id
        var fetch = FetchDescriptor<CityModel>(
            predicate: #Predicate { $0.id == idToFind }
        )
        fetch.fetchLimit = 1
        guard let city = try ctx.fetch(fetch).first else {
            throw CityError.notFound
        }
        ctx.delete(city)
        try ctx.save()
        notifyCityStoreDidChange()

        // 清理该城市关联的提醒持久化数据与通知
        if let modelContainer {
            Task {
                let reminderService = CityReminderService(modelContainer: modelContainer)
                await reminderService.deleteReminders(cityID: id)
            }
        }
    }
    
    func deleteCities(ids: [UUID], context: ModelContext? = nil) throws {
        guard !ids.isEmpty else { return }
        let ctx = try resolveContext(context)
        for id in ids {
            let idToFind = id
            var fetch = FetchDescriptor<CityModel>(
                predicate: #Predicate { $0.id == idToFind }
            )
            fetch.fetchLimit = 1
            if let city = try ctx.fetch(fetch).first {
                ctx.delete(city)
            }
        }
        try ctx.save()
        notifyCityStoreDidChange()

        // 清理关联的提醒持久化数据与通知
        if let modelContainer {
            Task {
                let reminderService = CityReminderService(modelContainer: modelContainer)
                await reminderService.deleteReminders(cityIDs: ids)
            }
        }
    }
    
    func getAllCities(context: ModelContext? = nil) throws -> [CityModel] {
        let ctx = try resolveContext(context)
        let fetch = FetchDescriptor<CityModel>(sortBy: [SortDescriptor(\.sortIndex)])
        return try ctx.fetch(fetch)
    }
    
    func getMaxSortIndex(context: ModelContext? = nil) throws -> Int {
        let ctx = try resolveContext(context)
        var fetch = FetchDescriptor<CityModel>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        fetch.fetchLimit = 1
        let result = try ctx.fetch(fetch)
        return result.first?.sortIndex ?? -1
    }
    
    func updateCitySortIndex(id: UUID, sortIndex: Int, context: ModelContext? = nil) throws {
        let ctx = try resolveContext(context)
        let idToFind = id
        var fetch = FetchDescriptor<CityModel>(
            predicate: #Predicate { $0.id == idToFind }
        )
        fetch.fetchLimit = 1
        guard let city = try ctx.fetch(fetch).first else {
            throw CityError.notFound
        }
        city.sortIndex = sortIndex
        try ctx.save()
        notifyCityStoreDidChange()
    }
    
    func reorderCities(_ cities: [CityModel], context: ModelContext? = nil) throws {
        let ctx = try resolveContext(context)
        for (index, city) in cities.enumerated() {
            city.sortIndex = index
        }
        try ctx.save()
        notifyCityStoreDidChange()
    }
    
    func hasCity(cityEn: String, timezoneId: String, context: ModelContext? = nil) throws -> Bool {
        let ctx = try resolveContext(context)
        return try findExisting(cityEn: cityEn, timezoneId: timezoneId, context: ctx) != nil
    }
    
    // MARK: - City Name Matching（静态方法，供 AppEnvironment 等外部调用）
    
    /// 内置城市目录在进程内只读取、解码一次。
    private static let catalog: [CitySuggestion] = {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cities = try? JSONDecoder().decode([CitySuggestion].self, from: data) else {
            return []
        }
        return cities
    }()

    private static let countryCodesByIdentity: [String: String] = {
        var result: [String: String] = [:]
        for city in catalog where !city.country.isEmpty {
            result[CityIdentity.key(cityEn: city.cityEn, timezoneId: city.timezoneId)] = city.country
        }
        return result
    }()

    private static let cityByTimezone: [String: CitySuggestion] = {
        var result: [String: CitySuggestion] = [:]
        for city in catalog where result[city.timezoneId] == nil {
            result[city.timezoneId] = city
        }
        return result
    }()

    /// 全量城市目录（已做进程级缓存），供城市选择页等需要完整列表的场景复用。
    static func allCities() -> [CitySuggestion]? {
        catalog.isEmpty ? nil : catalog
    }

    /// 在内置城市列表中查找与指定时区匹配的城市；找不到则用时区标识符派生名称。
    static func matchCity(for timezoneId: String) -> (name: String, en: String) {
        if let match = cityByTimezone[timezoneId] {
            return (match.cityName, match.cityEn)
        }
        let raw = timezoneId.split(separator: "/").last.map(String.init) ?? timezoneId
        let derived = raw.replacingOccurrences(of: "_", with: " ")
        return (derived, derived)
    }

    /// 按中文名 + 时区匹配城市。用于旧数据缺少英文名时回填，避免同一时区下误取目录中的首个城市。
    static func matchCity(cityName: String, timezoneId: String) -> (name: String, en: String) {
        if let match = catalog.first(where: {
            $0.cityName == cityName && $0.timezoneId == timezoneId
        }) {
            return (match.cityName, match.cityEn)
        }
        return matchCity(for: timezoneId)
    }

    /// 内置城市目录补全国家码（用于兼容旧数据缺失 country 字段）。
    static func countryCode(cityEn: String, timezoneId: String) -> String {
        countryCodesByIdentity[CityIdentity.key(cityEn: cityEn, timezoneId: timezoneId)] ?? ""
    }
}

enum CityError: Error, Equatable {
    case alreadyExists
    case notFound
    case databaseError(String)
    case storeUnavailable
}

private extension CityService {
    func notifyCityStoreDidChange() {
        NotificationCenter.default.post(name: .cityStoreDidChange, object: nil)
    }
}
