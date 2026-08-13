import Foundation
import Combine

final class CityPickerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var cityGroups: [ContinentGroup] = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    
    private let cityService = CityService.shared
    
    private var allCities: [CitySuggestion] = []
    
    init() {
        loadCities()
        
        $searchText
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.filterCities(text: text)
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Load Cities from JSON
    
    /// 城市数据静态缓存：首次加载后复用，避免 CityPickerView/CitySelectorView 重复 IO 与解码
    private enum CityDataCache {
        private static var cached: [CitySuggestion]?
        private static let lock = NSLock()

        static func load() -> [CitySuggestion]? {
            lock.lock()
            defer { lock.unlock() }
            if let cached = cached { return cached }
            guard let url = Bundle.main.url(forResource: "cities", withExtension: "json") else {
                return nil
            }
            do {
                let data = try Data(contentsOf: url)
                let cities = try JSONDecoder().decode([CitySuggestion].self, from: data)
                cached = cities
                return cities
            } catch {
                return nil
            }
        }
    }

    private func loadCities() {
        viewState = .loading

        guard let cities = CityDataCache.load() else {
            viewState = .failure(String(localized: "city.data.not.found"))
            errorMessage = String(localized: "city.data.not.found")
            return
        }

        allCities = cities
        cityGroups = groupByContinent(allCities)
        viewState = .idle
    }
    
    // MARK: - Group & Filter
    
    private let continentOrder = [
        "hot",
        "asia",
        "europe",
        "america",
        "oceania",
        "africa"
    ]

    private func localizedContinentName(_ continent: String) -> String {
        switch continent {
        case "hot": return String(localized: "continent.hot")
        case "asia": return String(localized: "continent.asia")
        case "europe": return String(localized: "continent.europe")
        case "america": return String(localized: "continent.america")
        case "oceania": return String(localized: "continent.oceania")
        case "africa": return String(localized: "continent.africa")
        default: return continent
        }
    }
    
    private func groupByContinent(_ cities: [CitySuggestion]) -> [ContinentGroup] {
        let groups = Dictionary(grouping: cities, by: { $0.continent })
        return continentOrder.compactMap { continent in
            groups[continent].map { ContinentGroup(name: localizedContinentName(continent), cities: $0) }
        }
    }
    
    private func filterCities(text: String) {
        guard !text.isEmpty else {
            cityGroups = groupByContinent(allCities)
            return
        }
        
        let lowerText = text.lowercased()
        
        // 先尝试精确匹配（包含）
        var filtered = allCities.filter { city in
            city.cityName.lowercased().contains(lowerText) ||
            city.cityEn.lowercased().contains(lowerText)
        }
        
        // 如果没有精确匹配，尝试模糊匹配（编辑距离）
        if filtered.isEmpty {
            filtered = allCities.compactMap { city in
                let nameDistance = lowerText.levenshteinDistance(to: city.cityName.lowercased())
                let enDistance = lowerText.levenshteinDistance(to: city.cityEn.lowercased())
                let minDistance = min(nameDistance, enDistance)
                let threshold = max(1, lowerText.count / 2)
                return minDistance <= threshold ? city : nil
            }
        }
        
        cityGroups = filtered.isEmpty ? [] : groupByContinent(filtered)
    }
    
    // MARK: - City Exists Check
    
    /// 简化异步检查：直接在 Task 中调用同步方法
    func checkCityExists(cityName: String, timezoneId: String) async -> Bool {
        do {
            return try await cityService.hasCity(cityName: cityName, timezoneId: timezoneId)
        } catch {
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
}