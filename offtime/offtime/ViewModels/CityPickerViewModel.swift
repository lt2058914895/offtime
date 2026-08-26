import Foundation
import Combine

final class CityPickerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var cityGroups: [CountryGroup] = []
    @Published var searchResults: [SearchResultCity] = []
    @Published var indexLetters: [String] = []
    @Published var matchedCountries: [CountryMatch] = []
    @Published var selectedCountry: CountryMatch?
    @Published var selectedCountryCities: [CitySuggestion] = []
    @Published var addedCityKeys: Set<String> = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?

    /// 搜索结果条目：城市 + 所属国家名（用于副标题消歧）
    struct SearchResultCity: Identifiable {
        let city: CitySuggestion
        let countryName: String
        var id: String { city.id }
    }

    /// 国家匹配结果：搜索时优先展示，点击后查看该国全部城市
    struct CountryMatch: Identifiable {
        let code: String
        let name: String
        let cities: [CitySuggestion]
        var id: String { code }
    }

    private let cityService = CityService.shared

    private var allCities: [CitySuggestion] = []
    private var cachedCountryNames: [String: String] = [:]
    private var cachedPinyin: [String: String] = [:]

    var isSearching: Bool { !searchText.isEmpty }

    init() {
        loadCities()
        refreshAddedCities()

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
        cityGroups = groupByCountry(allCities)
        viewState = .idle
    }

    // MARK: - 国家名

    private static var displayLocale: Locale {
        let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        switch language {
        case "en": return Locale(identifier: "en_US")
        case "ja": return Locale(identifier: "ja_JP")
        case "ko": return Locale(identifier: "ko_KR")
        default: return Locale(identifier: "zh_CN")
        }
    }

    private static var englishLocale = Locale(identifier: "en_US")

    /// 当前是否中文环境（决定索引与排序是否使用拼音）
    private static var isChineseLocale: Bool {
        (Bundle.main.preferredLocalizations.first ?? "zh-Hans").hasPrefix("zh")
    }

    /// 当前界面语言下的国家名（缓存）
    private func countryName(for code: String) -> String {
        if let cached = cachedCountryNames[code] { return cached }
        let name = Self.displayLocale.localizedString(forRegionCode: code) ?? code
        cachedCountryNames[code] = name
        return name
    }

    /// 英文国家名（用于搜索匹配）
    private func countryNameEn(for code: String) -> String {
        Self.englishLocale.localizedString(forRegionCode: code) ?? code
    }

    // MARK: - 分组（按国家）

    private func groupByCountry(_ cities: [CitySuggestion]) -> [CountryGroup] {
        let hot = cities.filter { $0.continent == "hot" }
        let arctic = cities.filter { $0.continent == "arctic" }
        let antarctica = cities.filter { $0.continent == "antarctica" }
        let rest = cities.filter {
            $0.continent != "hot" && $0.continent != "arctic" && $0.continent != "antarctica"
        }

        var groups = Dictionary(grouping: rest, by: { $0.country }).compactMap { code, items in
            CountryGroup(
                code: code,
                name: countryName(for: code),
                indexLetter: indexLetter(for: code),
                cities: items.sorted {
                    $0.cityName.localizedStandardCompare($1.cityName) == .orderedAscending
                }
            )
        }
        groups.sort {
            countrySortKey(code: $0.code, name: $0.name)
                < countrySortKey(code: $1.code, name: $1.name)
        }
        indexLetters = NSOrderedSet(array: groups.map { $0.indexLetter }).array as? [String] ?? []

        var special: [CountryGroup] = []
        if !arctic.isEmpty {
            special.append(
                CountryGroup(
                    code: "arctic",
                    name: String(localized: "continent.arctic"),
                    indexLetter: "★",
                    cities: arctic.sorted {
                        $0.cityName.localizedStandardCompare($1.cityName) == .orderedAscending
                    }
                )
            )
        }
        if !antarctica.isEmpty {
            special.append(
                CountryGroup(
                    code: "antarctica",
                    name: String(localized: "continent.antarctica"),
                    indexLetter: "★",
                    cities: antarctica.sorted {
                        $0.cityName.localizedStandardCompare($1.cityName) == .orderedAscending
                    }
                )
            )
        }
        if !hot.isEmpty {
            special.insert(
                CountryGroup(
                    code: "hot",
                    name: String(localized: "continent.hot"),
                    indexLetter: "★",
                    cities: hot
                ),
                at: 0
            )
        }
        return special + groups
    }

    // MARK: - 索引与排序（统一按英文国家名）

    /// 拼音缓存：中文环境下排序与索引都需要多次转换
    private func pinyin(of text: String) -> String {
        if let cached = cachedPinyin[text] { return cached }
        var result = text.lowercased()
        if text.range(of: "\\p{Han}", options: .regularExpression) != nil {
            let mutable = NSMutableString(string: text) as CFMutableString
            if CFStringTransform(mutable, nil, kCFStringTransformToLatin, false) {
                CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
                result = (mutable as String).lowercased().filter { !$0.isWhitespace }
            }
        }
        cachedPinyin[text] = result
        return result
    }

    /// 国家分组的索引字母：统一取英文名首字母，避免不同语言下索引与列表错位
    private func indexLetter(for code: String) -> String {
        let source = countryNameEn(for: code).lowercased()
        guard let first = source.first else { return "#" }
        let letter = String(first).uppercased()
        return letter.range(of: "[A-Z]", options: .regularExpression) != nil ? letter : "#"
    }

    /// 国家排序键：统一按英文名，保证分组顺序与索引条一致
    private func countrySortKey(code: String, name: String) -> String {
        countryNameEn(for: code).lowercased()
    }

    // MARK: - 搜索

    private func filterCities(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cityGroups = groupByCountry(allCities)
            searchResults = []
            matchedCountries = []
            selectedCountry = nil
            selectedCountryCities = []
            return
        }

        // 已选中国家：仅当关键词仍为该国家名时展示该国城市，否则回退普通搜索
        if let selected = selectedCountry, trimmed == selected.name {
            matchedCountries = []
            searchResults = selectedCountryCities.map {
                SearchResultCity(city: $0, countryName: selected.name)
            }
            cityGroups = []
            return
        }
        selectedCountry = nil
        selectedCountryCities = []

        let lowerText = trimmed.lowercased()

        // 国家匹配（优先展示，点击可查看该国全部城市）
        matchedCountries = findCountries(query: lowerText)

        // 先尝试精确匹配（包含）
        var filtered = allCities.filter { city in
            city.cityName.lowercased().contains(lowerText) ||
            city.cityEn.lowercased().contains(lowerText) ||
            city.country.lowercased().contains(lowerText) ||
            countryName(for: city.country).lowercased().contains(lowerText) ||
            countryNameEn(for: city.country).lowercased().contains(lowerText)
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

        searchResults = filtered.map { city in
            SearchResultCity(city: city, countryName: countryName(for: city.country))
        }
        searchResults.sort {
            $0.city.cityName.localizedStandardCompare($1.city.cityName) == .orderedAscending
        }
        cityGroups = []
    }

    /// 查找匹配关键词的国家（支持国家码 / 中文名 / 英文名 / 中文拼音）
    private func findCountries(query: String) -> [CountryMatch] {
        let grouped = Dictionary(grouping: allCities.filter { city in
            city.continent != "hot" && city.continent != "arctic" && city.continent != "antarctica"
        }, by: { $0.country })

        let matches = grouped.compactMap { code, cities -> CountryMatch? in
            let name = countryName(for: code)
            let enName = countryNameEn(for: code)
            let pinyinName = Self.isChineseLocale ? pinyin(of: name) : ""
            let hit = code.lowercased().contains(query)
                || name.lowercased().contains(query)
                || enName.lowercased().contains(query)
                || (!pinyinName.isEmpty && pinyinName.contains(query))
            return hit ? CountryMatch(code: code, name: name, cities: cities) : nil
        }
        return matches.sorted {
            countrySortKey(code: $0.code, name: $0.name)
                < countrySortKey(code: $1.code, name: $1.name)
        }
    }

    // MARK: - 选中国家

    /// 进入国家视图：展示该国全部城市
    func selectCountry(_ match: CountryMatch) {
        selectedCountry = match
        selectedCountryCities = match.cities.sorted {
            $0.cityName.localizedStandardCompare($1.cityName) == .orderedAscending
        }
        searchText = match.name
    }


    // MARK: - 已添加城市标记

    func refreshAddedCities() {
        Task { @MainActor in
            let cities = (try? cityService.getAllCities()) ?? []
            addedCityKeys = Set(cities.map {
                CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId)
            })
        }
    }

    // MARK: - City Exists Check

    /// 简化异步检查：直接在 Task 中调用同步方法
    func checkCityExists(cityEn: String, timezoneId: String) async -> Bool {
        do {
            return try await cityService.hasCity(cityEn: cityEn, timezoneId: timezoneId)
        } catch {
            return false
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
}
