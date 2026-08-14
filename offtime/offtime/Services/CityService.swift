import Foundation
import SwiftData

@MainActor
final class CityService {
    static let shared = CityService()
    
    private init() {}
    
    // MARK: - ModelContext 获取
    
    /// 由 AppEnvironment 在启动时注入
    var modelContainer: ModelContainer!
    
    /// 便捷获取主上下文
    private var mainContext: ModelContext {
        modelContainer.mainContext
    }
    
    // MARK: - City CRUD
    
    func addCity(cityName: String, cityEn: String, timezoneId: String, context: ModelContext? = nil) throws {
        let ctx = context ?? mainContext
        
        // 判重：(cityName, timezoneId) 联合唯一
        var fetch = FetchDescriptor<CityModel>(
            predicate: #Predicate { $0.cityName == cityName && $0.timezoneId == timezoneId }
        )
        fetch.fetchLimit = 1
        let existing = try ctx.fetch(fetch)
        if !existing.isEmpty {
            throw CityError.alreadyExists
        }
        
        let maxSortIndex = try getMaxSortIndex(context: ctx)
        let city = CityModel(
            cityName: cityName,
            cityEn: cityEn,
            timezoneId: timezoneId,
            sortIndex: maxSortIndex + 1
        )
        ctx.insert(city)
        try ctx.save()
    }
    
    func deleteCity(id: UUID, context: ModelContext? = nil) throws {
        let ctx = context ?? mainContext
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
    }
    
    func deleteCities(ids: [UUID], context: ModelContext? = nil) throws {
        guard !ids.isEmpty else { return }
        let ctx = context ?? mainContext
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
    }
    
    func getAllCities(context: ModelContext? = nil) throws -> [CityModel] {
        let ctx = context ?? mainContext
        let fetch = FetchDescriptor<CityModel>(sortBy: [SortDescriptor(\.sortIndex)])
        return try ctx.fetch(fetch)
    }
    
    func getMaxSortIndex(context: ModelContext? = nil) throws -> Int {
        let ctx = context ?? mainContext
        var fetch = FetchDescriptor<CityModel>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        fetch.fetchLimit = 1
        let result = try ctx.fetch(fetch)
        return result.first?.sortIndex ?? -1
    }
    
    func updateCitySortIndex(id: UUID, sortIndex: Int, context: ModelContext? = nil) throws {
        let ctx = context ?? mainContext
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
    }
    
    func reorderCities(_ cities: [CityModel], context: ModelContext? = nil) throws {
        let ctx = context ?? mainContext
        for (index, city) in cities.enumerated() {
            city.sortIndex = index
        }
        try ctx.save()
    }
    
    func hasCity(cityName: String, timezoneId: String, context: ModelContext? = nil) throws -> Bool {
        let ctx = context ?? mainContext
        var fetch = FetchDescriptor<CityModel>(
            predicate: #Predicate { $0.cityName == cityName && $0.timezoneId == timezoneId }
        )
        fetch.fetchLimit = 1
        return !(try ctx.fetch(fetch)).isEmpty
    }
    
    // MARK: - Import / Export
    
    func exportCities(context: ModelContext? = nil) throws -> Data {
        let cities = try getAllCities(context: context)
        let items = cities.map { $0.toItem() }
        let envelope = CitiesExportEnvelope(
            schemaVersion: CitiesExportEnvelope.currentSchemaVersion,
            cities: items
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(envelope)
    }
    
    func importCities(from data: Data, strategy: ImportStrategy, context: ModelContext? = nil) throws {
        let ctx = context ?? mainContext
        let decoder = JSONDecoder()
        let importedCities: [CityItem]
        
        if let envelope = try? decoder.decode(CitiesExportEnvelope.self, from: data) {
            guard envelope.schemaVersion == CitiesExportEnvelope.currentSchemaVersion else {
                throw CityError.unsupportedSchemaVersion
            }
            importedCities = envelope.cities
        } else {
            importedCities = try decoder.decode([CityItem].self, from: data)
        }
        
        switch strategy {
        case .replace:
            // 清空现有城市
            let existing = try ctx.fetch(FetchDescriptor<CityModel>())
            for city in existing {
                ctx.delete(city)
            }
            // 插入导入的城市
            for (index, item) in importedCities.enumerated() {
                let model = CityModel(
                    id: item.id,
                    cityName: item.cityName,
                    cityEn: item.cityEn,
                    timezoneId: item.timezoneId,
                    sortIndex: index,
                    workStartHour: item.workStartHour,
                    workEndHour: item.workEndHour,
                    localWorkStart: item.localWorkStart,
                    localWorkEnd: item.localWorkEnd
                )
                ctx.insert(model)
            }
        case .merge:
            let existing = try getAllCities(context: ctx)
            let existingKeys = Set(existing.map { "\($0.cityName)|\($0.timezoneId)" })
            var maxIndex = existing.map(\.sortIndex).max() ?? -1
            
            for item in importedCities {
                let key = "\(item.cityName)|\(item.timezoneId)"
                if !existingKeys.contains(key) {
                    maxIndex += 1
                    let model = CityModel(
                        id: item.id,
                        cityName: item.cityName,
                        cityEn: item.cityEn,
                        timezoneId: item.timezoneId,
                        sortIndex: maxIndex,
                        workStartHour: item.workStartHour,
                        workEndHour: item.workEndHour,
                        localWorkStart: item.localWorkStart,
                        localWorkEnd: item.localWorkEnd
                    )
                    ctx.insert(model)
                }
            }
        }
        try ctx.save()
    }
    
    // MARK: - City Name Matching（静态方法，供 AppEnvironment 等外部调用）
    
    /// 在内置城市列表中查找与指定时区匹配的城市；找不到则用时区标识符派生名称。
    static func matchCity(for timezoneId: String) -> (name: String, en: String) {
        if let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let cities = try? JSONDecoder().decode([CitySuggestion].self, from: data),
           let match = cities.first(where: { $0.timezoneId == timezoneId }) {
            return (match.cityName, match.cityEn)
        }
        let raw = timezoneId.split(separator: "/").last.map(String.init) ?? timezoneId
        let derived = raw.replacingOccurrences(of: "_", with: " ")
        return (derived, derived)
    }
}

enum CityError: Error, Equatable {
    case alreadyExists
    case notFound
    case databaseError(String)
    case unsupportedSchemaVersion
}
