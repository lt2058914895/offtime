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
}

enum CityError: Error, Equatable {
    case alreadyExists
    case notFound
    case databaseError(String)
}