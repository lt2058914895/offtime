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
    
    private func loadCities() {
        viewState = .loading
        
        // 始终使用默认城市（包含完整城市列表）
        loadDefaultCities()
        
        viewState = .idle
    }
    
    private func loadDefaultCities() {
        let hotCities = [
            CitySuggestion(id: "1", cityName: "北京", cityEn: "Beijing", timezoneId: "Asia/Shanghai", continent: "热门"),
            CitySuggestion(id: "2", cityName: "上海", cityEn: "Shanghai", timezoneId: "Asia/Shanghai", continent: "热门"),
            CitySuggestion(id: "3", cityName: "香港", cityEn: "Hong Kong", timezoneId: "Asia/Hong_Kong", continent: "热门"),
            CitySuggestion(id: "4", cityName: "台北", cityEn: "Taipei", timezoneId: "Asia/Taipei", continent: "热门"),
            CitySuggestion(id: "5", cityName: "东京", cityEn: "Tokyo", timezoneId: "Asia/Tokyo", continent: "热门"),
            CitySuggestion(id: "6", cityName: "新加坡", cityEn: "Singapore", timezoneId: "Asia/Singapore", continent: "热门"),
            CitySuggestion(id: "7", cityName: "伦敦", cityEn: "London", timezoneId: "Europe/London", continent: "热门"),
            CitySuggestion(id: "8", cityName: "纽约", cityEn: "New York", timezoneId: "America/New_York", continent: "热门"),
            CitySuggestion(id: "9", cityName: "洛杉矶", cityEn: "Los Angeles", timezoneId: "America/Los_Angeles", continent: "热门"),
            CitySuggestion(id: "10", cityName: "悉尼", cityEn: "Sydney", timezoneId: "Australia/Sydney", continent: "热门"),
        ]
        
        let asiaCities = [
            CitySuggestion(id: "11", cityName: "首尔", cityEn: "Seoul", timezoneId: "Asia/Seoul", continent: "亚洲"),
            CitySuggestion(id: "12", cityName: "曼谷", cityEn: "Bangkok", timezoneId: "Asia/Bangkok", continent: "亚洲"),
            CitySuggestion(id: "13", cityName: "迪拜", cityEn: "Dubai", timezoneId: "Asia/Dubai", continent: "亚洲"),
            CitySuggestion(id: "14", cityName: "孟买", cityEn: "Mumbai", timezoneId: "Asia/Kolkata", continent: "亚洲"),
            CitySuggestion(id: "15", cityName: "新德里", cityEn: "New Delhi", timezoneId: "Asia/Kolkata", continent: "亚洲"),
            CitySuggestion(id: "16", cityName: "马尼拉", cityEn: "Manila", timezoneId: "Asia/Manila", continent: "亚洲"),
            CitySuggestion(id: "17", cityName: "雅加达", cityEn: "Jakarta", timezoneId: "Asia/Jakarta", continent: "亚洲"),
            CitySuggestion(id: "18", cityName: "吉隆坡", cityEn: "Kuala Lumpur", timezoneId: "Asia/Kuala_Lumpur", continent: "亚洲"),
        ]
        
        let europeCities = [
            CitySuggestion(id: "19", cityName: "巴黎", cityEn: "Paris", timezoneId: "Europe/Paris", continent: "欧洲"),
            CitySuggestion(id: "20", cityName: "柏林", cityEn: "Berlin", timezoneId: "Europe/Berlin", continent: "欧洲"),
            CitySuggestion(id: "21", cityName: "罗马", cityEn: "Rome", timezoneId: "Europe/Rome", continent: "欧洲"),
            CitySuggestion(id: "22", cityName: "马德里", cityEn: "Madrid", timezoneId: "Europe/Madrid", continent: "欧洲"),
            CitySuggestion(id: "23", cityName: "阿姆斯特丹", cityEn: "Amsterdam", timezoneId: "Europe/Amsterdam", continent: "欧洲"),
            CitySuggestion(id: "24", cityName: "莫斯科", cityEn: "Moscow", timezoneId: "Europe/Moscow", continent: "欧洲"),
            CitySuggestion(id: "35", cityName: "萨格勒布", cityEn: "Zagreb", timezoneId: "Europe/Zagreb", continent: "欧洲"),
            CitySuggestion(id: "36", cityName: "布达佩斯", cityEn: "Budapest", timezoneId: "Europe/Budapest", continent: "欧洲"),
            CitySuggestion(id: "37", cityName: "布拉格", cityEn: "Prague", timezoneId: "Europe/Prague", continent: "欧洲"),
            CitySuggestion(id: "38", cityName: "维也纳", cityEn: "Vienna", timezoneId: "Europe/Vienna", continent: "欧洲"),
            CitySuggestion(id: "39", cityName: "华沙", cityEn: "Warsaw", timezoneId: "Europe/Warsaw", continent: "欧洲"),
            CitySuggestion(id: "40", cityName: "斯德哥尔摩", cityEn: "Stockholm", timezoneId: "Europe/Stockholm", continent: "欧洲"),
            CitySuggestion(id: "41", cityName: "哥本哈根", cityEn: "Copenhagen", timezoneId: "Europe/Copenhagen", continent: "欧洲"),
            CitySuggestion(id: "42", cityName: "奥斯陆", cityEn: "Oslo", timezoneId: "Europe/Oslo", continent: "欧洲"),
            CitySuggestion(id: "43", cityName: "赫尔辛基", cityEn: "Helsinki", timezoneId: "Europe/Helsinki", continent: "欧洲"),
            CitySuggestion(id: "44", cityName: "布鲁塞尔", cityEn: "Brussels", timezoneId: "Europe/Brussels", continent: "欧洲"),
            CitySuggestion(id: "45", cityName: "里斯本", cityEn: "Lisbon", timezoneId: "Europe/Lisbon", continent: "欧洲"),
            CitySuggestion(id: "46", cityName: "雅典", cityEn: "Athens", timezoneId: "Europe/Athens", continent: "欧洲"),
            CitySuggestion(id: "47", cityName: "日内瓦", cityEn: "Geneva", timezoneId: "Europe/Zurich", continent: "欧洲"),
            CitySuggestion(id: "48", cityName: "苏黎世", cityEn: "Zurich", timezoneId: "Europe/Zurich", continent: "欧洲"),
            CitySuggestion(id: "49", cityName: "爱丁堡", cityEn: "Edinburgh", timezoneId: "Europe/London", continent: "欧洲"),
            CitySuggestion(id: "50", cityName: "都柏林", cityEn: "Dublin", timezoneId: "Europe/Dublin", continent: "欧洲"),
            CitySuggestion(id: "51", cityName: "索菲亚", cityEn: "Sofia", timezoneId: "Europe/Sofia", continent: "欧洲"),
            CitySuggestion(id: "52", cityName: "布加勒斯特", cityEn: "Bucharest", timezoneId: "Europe/Bucharest", continent: "欧洲"),
            CitySuggestion(id: "53", cityName: "贝尔格莱德", cityEn: "Belgrade", timezoneId: "Europe/Belgrade", continent: "欧洲"),
            CitySuggestion(id: "54", cityName: "卢森堡", cityEn: "Luxembourg", timezoneId: "Europe/Luxembourg", continent: "欧洲"),
        ]
        
        let americaCities = [
            CitySuggestion(id: "25", cityName: "芝加哥", cityEn: "Chicago", timezoneId: "America/Chicago", continent: "美洲"),
            CitySuggestion(id: "26", cityName: "多伦多", cityEn: "Toronto", timezoneId: "America/Toronto", continent: "美洲"),
            CitySuggestion(id: "27", cityName: "温哥华", cityEn: "Vancouver", timezoneId: "America/Vancouver", continent: "美洲"),
            CitySuggestion(id: "28", cityName: "卡尔加里", cityEn: "Calgary", timezoneId: "America/Edmonton", continent: "美洲"),
            CitySuggestion(id: "29", cityName: "圣保罗", cityEn: "Sao Paulo", timezoneId: "America/Sao_Paulo", continent: "美洲"),
            CitySuggestion(id: "30", cityName: "墨西哥城", cityEn: "Mexico City", timezoneId: "America/Mexico_City", continent: "美洲"),
        ]
        
        let oceaniaCities = [
            CitySuggestion(id: "31", cityName: "奥克兰", cityEn: "Auckland", timezoneId: "Pacific/Auckland", continent: "大洋洲"),
            CitySuggestion(id: "32", cityName: "墨尔本", cityEn: "Melbourne", timezoneId: "Australia/Melbourne", continent: "大洋洲"),
            CitySuggestion(id: "33", cityName: "布里斯班", cityEn: "Brisbane", timezoneId: "Australia/Brisbane", continent: "大洋洲"),
        ]
        
        let africaCities = [
            CitySuggestion(id: "34", cityName: "开罗", cityEn: "Cairo", timezoneId: "Africa/Cairo", continent: "非洲"),
            CitySuggestion(id: "35", cityName: "约翰内斯堡", cityEn: "Johannesburg", timezoneId: "Africa/Johannesburg", continent: "非洲"),
        ]
        
        allCities = hotCities + asiaCities + europeCities + americaCities + oceaniaCities + africaCities
        cityGroups = groupByContinent(allCities)
    }
    
    private func groupByContinent(_ cities: [CitySuggestion]) -> [ContinentGroup] {
        let groups = Dictionary(grouping: cities, by: { $0.continent })
        
        let sortedContinents = ["热门", "亚洲", "欧洲", "美洲", "大洋洲", "非洲"]
        var result: [ContinentGroup] = []
        
        for continent in sortedContinents {
            if let cities = groups[continent] {
                result.append(ContinentGroup(name: continent, cities: cities))
            }
        }
        
        return result
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
                // 根据搜索词长度设置不同的容错阈值
                let threshold = max(1, lowerText.count / 2)
                return minDistance <= threshold ? city : nil
            }
        }
        
        if filtered.isEmpty {
            cityGroups = []
        } else {
            cityGroups = groupByContinent(filtered)
        }
    
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
                    matrix[i-1][j] + 1,     // 删除
                    matrix[i][j-1] + 1,     // 插入
                    matrix[i-1][j-1] + cost // 替换
                )
            }
        }
        
        return matrix[len1][len2]
    }
    
    func checkCityExists(cityName: String) async -> Bool {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    do {
                        let exists = try cityService.hasCity(cityName: cityName)
                        continuation.resume(returning: exists)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
}
