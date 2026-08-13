import Foundation

final class CityService {
    static let shared = CityService()
    
    private let repository = DatabaseRepository.shared
    
    private init() {}
    
    func addCity(cityName: String, cityEn: String, timezoneId: String) throws {
        let exists = try repository.hasCity(cityName: cityName, timezoneId: timezoneId)
        if exists {
            throw CityError.alreadyExists
        }
        
        let maxIndex = try repository.getMaxSortIndex()
        let record = CityRecord(
            id: UUID().uuidString,
            cityName: cityName,
            cityEn: cityEn,
            timezoneId: timezoneId,
            sortIndex: maxIndex + 1,
            isTop: 0
        )
        
        try repository.addCity(record)
    }
    
    func deleteCity(id: UUID) throws {
        try repository.deleteCity(id: id.uuidString)
    }

    /// 批量删除城市，事务保证原子性：任一删除失败则整体回滚。
    /// 直接调用 Repository 的单次 sync 事务方法，避免在事务块里再调用各自 dbQueue.sync 的 deleteCity 嵌套 sync 死锁。
    func deleteCities(ids: [UUID]) throws {
        try repository.deleteCities(ids: ids.map { $0.uuidString })
    }
    
    func getAllCities() throws -> [CityItem] {
        let records = try repository.getAllCities()
        return records.compactMap { record in
            guard let uuid = UUID(uuidString: record.id) else { return nil }
            return CityItem(
                id: uuid,
                cityName: record.cityName,
                cityEn: record.cityEn,
                timezoneId: record.timezoneId,
                sortIndex: record.sortIndex,
                isTop: record.isTop == 1
            )
        }
    }
    
    func updateCitySortIndex(id: UUID, sortIndex: Int) throws {
        try repository.updateCitySortIndex(id: id.uuidString, sortIndex: sortIndex)
    }
    
    func updateCityTop(id: UUID, isTop: Bool) throws {
        try repository.updateCityTop(id: id.uuidString, isTop: isTop)
    }
    
    func hasCity(cityName: String, timezoneId: String) throws -> Bool {
        try repository.hasCity(cityName: cityName, timezoneId: timezoneId)
    }
    
    func reorderCities(_ cities: [CityItem]) throws {
        let idIndexPairs = cities.enumerated().map { (index, city) in
            (id: city.id.uuidString, sortIndex: index)
        }
        try repository.updateSortIndices(idIndexPairs)
    }

    func exportCities() throws -> Data {
        let cities = try getAllCities()
        let envelope = CitiesExportEnvelope(
            schemaVersion: CitiesExportEnvelope.currentSchemaVersion,
            cities: cities
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(envelope)
    }
    
    /// 导入城市列表。支持两种策略：
    /// - .replace: 清空后整体写入
    /// - .merge: 保留现有城市，按 (cityName, timezoneId) 去重后追加
    /// 优先按 CitiesExportEnvelope 解码并校验 schemaVersion；失败则回退旧格式（纯 [CityItem]）以兼容历史导出文件。
    /// 直接调用 Repository 的单次 sync 事务方法，避免在事务块里再调用各自 dbQueue.sync 的方法嵌套 sync 死锁。
    func importCities(from data: Data, strategy: ImportStrategy) throws {
        let decoder = JSONDecoder()
        let importedCities: [CityItem]
        if let envelope = try? decoder.decode(CitiesExportEnvelope.self, from: data) {
            guard envelope.schemaVersion == CitiesExportEnvelope.currentSchemaVersion else {
                throw CityError.unsupportedSchemaVersion
            }
            importedCities = envelope.cities
        } else {
            // 兼容历史导出文件（无 schemaVersion 的纯数组）
            importedCities = try decoder.decode([CityItem].self, from: data)
        }

        let citiesToWrite: [CityItem]
        switch strategy {
        case .replace:
            citiesToWrite = importedCities
        case .merge:
            let existing = try getAllCities()
            let existingKeys = Set(existing.map { "\($0.cityName)|\($0.timezoneId)" })
            var merged = existing
            for city in importedCities {
                let key = "\(city.cityName)|\(city.timezoneId)"
                if !existingKeys.contains(key) {
                    merged.append(city)
                }
            }
            citiesToWrite = merged
        }

        let records = citiesToWrite.enumerated().map { index, city in
            CityRecord(
                id: city.id.uuidString,
                cityName: city.cityName,
                cityEn: city.cityEn,
                timezoneId: city.timezoneId,
                sortIndex: index,
                isTop: city.isTop ? 1 : 0
            )
        }
        try repository.replaceAllCities(records)
    }

    // MARK: - First Launch Seeding

    /// 首次启动时根据设备系统时区自动加入一个默认城市，避免空列表。
    /// 仅根据 `TimeZone.current` 推断，不请求定位权限、不联网。幂等：通过 app_config 的标志位保证只执行一次。
    /// - Returns: 是否为首次启动（标志位此前未设置）
    @discardableResult
    func seedDefaultCityIfFirstLaunch() throws -> Bool {
        let seededKey = "first_launch_seeded"
        if let flag = try? repository.getConfig(key: seededKey), flag == "1" {
            return false
        }
        // 仅当用户当前没有任何城市时才自动加入，避免给已在使用的老用户突然加城市
        let existing = try getAllCities()
        if existing.isEmpty {
            let timezoneId = TimeZone.current.identifier
            let (cityName, cityEn) = matchCity(for: timezoneId)
            try addCity(cityName: cityName, cityEn: cityEn, timezoneId: timezoneId)
        }
        try repository.saveConfig(key: seededKey, value: "1")
        return true
    }

    /// 在内置城市列表中查找与指定时区匹配的城市；找不到则用时区标识符派生名称。
    private func matchCity(for timezoneId: String) -> (name: String, en: String) {
        if let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let cities = try? JSONDecoder().decode([CitySuggestion].self, from: data),
           let match = cities.first(where: { $0.timezoneId == timezoneId }) {
            return (match.cityName, match.cityEn)
        }

        // 回退：取时区标识符最后一段（如 "Asia/Shanghai" → "Shanghai"）作为城市名
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