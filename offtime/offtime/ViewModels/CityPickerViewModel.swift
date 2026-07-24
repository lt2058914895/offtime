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
    
    private func loadCities() {
        viewState = .loading
        
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json") else {
            viewState = .failure("城市数据文件未找到")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            allCities = try decoder.decode([CitySuggestion].self, from: data)
            cityGroups = groupByContinent(allCities)
            viewState = .idle
        } catch {
            viewState = .failure("城市数据加载失败")
            errorMessage = "城市数据加载失败"
        }
    }
    
    // MARK: - Group & Filter
    
    private let continentOrder = ["热门", "亚洲", "欧洲", "美洲", "大洋洲", "非洲"]
    
    private func groupByContinent(_ cities: [CitySuggestion]) -> [ContinentGroup] {
        let groups = Dictionary(grouping: cities, by: { $0.continent })
        return continentOrder.compactMap { continent in
            groups[continent].map { ContinentGroup(name: continent, cities: $0) }
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
                let nameDistance = levenshteinDistance(lowerText, city.cityName.lowercased())
                let enDistance = levenshteinDistance(lowerText, city.cityEn.lowercased())
                let minDistance = min(nameDistance, enDistance)
                let threshold = max(1, lowerText.count / 2)
                return minDistance <= threshold ? city : nil
            }
        }
        
        cityGroups = filtered.isEmpty ? [] : groupByContinent(filtered)
    }
    
    /// 计算两个字符串之间的编辑距离（Levenshtein Distance）
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let len1 = s1.count
        let len2 = s2.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)
        
        for i in 0...len1 {
            matrix[i][0] = i
        }
        for j in 0...len2 {
            matrix[0][j] = j
        }
        
        let arr1 = Array(s1)
        let arr2 = Array(s2)
        
        for i in 1...len1 {
            for j in 1...len2 {
                let cost = arr1[i-1] == arr2[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }
        
        return matrix[len1][len2]
    }
    
    // MARK: - City Exists Check
    
    /// 简化异步检查：直接在 Task 中调用同步方法
    func checkCityExists(cityName: String) async -> Bool {
        do {
            return try cityService.hasCity(cityName: cityName)
        } catch {
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
}