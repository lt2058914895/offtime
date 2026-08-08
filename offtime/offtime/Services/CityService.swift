import Foundation

final class CityService {
    static let shared = CityService()
    
    private let repository = DatabaseRepository.shared
    
    private init() {}
    
    func addCity(cityName: String, cityEn: String, timezoneId: String) throws {
        let exists = try repository.hasCity(cityName: cityName)
        if exists {
            throw CityError.alreadyExists
        }
        
        let maxIndex = try getMaxSortIndex()
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
    
    func hasCity(cityName: String) throws -> Bool {
        try repository.hasCity(cityName: cityName)
    }
    
    func reorderCities(_ cities: [CityItem]) throws {
        for (index, city) in cities.enumerated() {
            try repository.updateCitySortIndex(id: city.id.uuidString, sortIndex: index)
        }
    }
    
    private func getMaxSortIndex() throws -> Int {
        let cities = try repository.getAllCities()
        return cities.map { $0.sortIndex }.max() ?? -1
    }
    
    func exportCities() throws -> Data {
        let cities = try getAllCities()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(cities)
    }
    
    /// 使用事务保护导入操作，确保原子性：失败时回滚，原有数据不丢失
    func importCities(from data: Data) throws {
        let decoder = JSONDecoder()
        let cities = try decoder.decode([CityItem].self, from: data)
        
        try repository.performTransaction {
            try repository.deleteAllCities()
            for (index, city) in cities.enumerated() {
                let record = CityRecord(
                    id: city.id.uuidString,
                    cityName: city.cityName,
                    cityEn: city.cityEn,
                    timezoneId: city.timezoneId,
                    sortIndex: index,
                    isTop: city.isTop ? 1 : 0
                )
                try repository.addCity(record)
            }
        }
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
}