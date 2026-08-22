import Foundation
import Combine
import SwiftData

/// 从会议页跳转转换器时的预填请求：指定源/目标时区与目标时刻（绝对时间）。
struct ConverterPrefill: Equatable, Hashable {
    let id: UUID
    let sourceTimezoneId: String
    let targetTimezoneId: String
    let date: Date?

    init(
        id: UUID = UUID(),
        sourceTimezoneId: String,
        targetTimezoneId: String,
        date: Date?
    ) {
        self.id = id
        self.sourceTimezoneId = sourceTimezoneId
        self.targetTimezoneId = targetTimezoneId
        self.date = date
    }
}

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published var sourceCity: CityModel?
    @Published var targetCity: CityModel?
    @Published var sourceDate: Date = Date()
    
    @Published var resultTime: String = ""
    @Published var resultDate: String = ""
    @Published var timeDifference: String = ""
    @Published var crossDay: String?
    
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    
    private let timezoneService = TimezoneService.shared
    private let cityService = CityService.shared
    
    @Published var availableCities: [CityModel] = []
    @Published var isSwapping: Bool = false
    
    init() {
        loadCities()
        
        $sourceCity
            .combineLatest($targetCity, $sourceDate)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] source, target, date in
                self?.convertTime(source: source, target: target, date: date)
            }
            .store(in: &cancellables)
        
        $use24Hour
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshFormat()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    func loadCities() {
        do {
            let cities = try cityService.getAllCities()
            availableCities = cities
            
            if sourceCity == nil && !cities.isEmpty {
                sourceCity = cities.first
            }
            if targetCity == nil && cities.count > 1 {
                targetCity = cities[1]
            }
        } catch {
            errorMessage = String(localized: "converter.load.cities.failed")
        }
    }
    
    func refreshFormat() {
        convertTime(source: sourceCity, target: targetCity, date: sourceDate)
    }

    func isCityDaytime(_ city: CityModel?) -> Bool {
        guard let city else { return true }
        return timezoneService.isDaytime(timezoneId: city.timezoneId, date: Date())
    }
    
    private func convertTime(source: CityModel?, target: CityModel?, date: Date) {
        guard let source = source, let target = target else {
            resultTime = String(localized: "converter.select.city.hint")
            resultDate = ""
            timeDifference = ""
            crossDay = nil
            return
        }
        
        guard let sourceTimezone = TimeZone(identifier: source.timezoneId),
              let targetTimezone = TimeZone(identifier: target.timezoneId) else {
            resultTime = String(localized: "converter.timezone.parse.failed")
            resultDate = ""
            timeDifference = ""
            crossDay = nil
            return
        }
        
        // 创建源时区日历，用于解释用户选择的时间组件
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = sourceTimezone
        
        // 获取用户选择的时间组件（年、月、日、时、分）
        // 注意：这里用源时区日历获取组件，但组件值是从date中提取的，date是DatePicker按本地时区解释的
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        
        // 关键：用源时区日历将时间组件重新解释为绝对时间
        // 这表示"用户选择的17:42是源时区（上海）的17:42"
        guard let absoluteDate = sourceCalendar.date(from: components) else {
            resultTime = String(localized: "converter.convert.failed")
            resultDate = ""
            timeDifference = ""
            crossDay = nil
            return
        }
        
        // 用目标时区格式化结果
        if use24Hour {
            resultTime = timezoneService.getLocalTime24(timezoneId: target.timezoneId, date: absoluteDate) ?? String(localized: "clock.time.parse.failed")
        } else {
            resultTime = timezoneService.getLocalTime12(timezoneId: target.timezoneId, date: absoluteDate) ?? String(localized: "clock.time.parse.failed")
        }
        resultDate = timezoneService.getLocalDate(timezoneId: target.timezoneId, date: absoluteDate) ?? String(localized: "clock.date.parse.failed")
        
        // 计算源时区和目标时区之间的时差（复用 TimezoneService）
        let diff = timezoneService.getTimeDifferenceBetween(
            sourceTimezoneId: source.timezoneId,
            targetTimezoneId: target.timezoneId,
            date: absoluteDate
        )
        timeDifference = diff.offset
        crossDay = diff.crossDay
        
        viewState = .idle
    }
    
    /// 应用外部跳转预填（如会议页推荐窗口）：按时区匹配已有城市，找不到时临时构建。
    func applyPrefill(sourceTimezoneId: String, targetTimezoneId: String, date: Date?) {
        let source = findOrMakeCity(timezoneId: sourceTimezoneId)
        let target = findOrMakeCity(timezoneId: targetTimezoneId)
        sourceCity = source
        targetCity = target
        if let date {
            sourceDate = date
        }
        refreshFormat()
    }

    private func findOrMakeCity(timezoneId: String) -> CityModel {
        if let match = availableCities.first(where: { $0.timezoneId == timezoneId }) {
            return match
        }
        let (name, en) = CityService.matchCity(for: timezoneId)
        return CityModel(cityName: name, cityEn: en, timezoneId: timezoneId)
    }

    func swapCities() {
        isSwapping = true
        let temp = sourceCity
        sourceCity = targetCity
        targetCity = temp
        Haptics.medium()
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.isSwapping = false
            }
        }
    }
    
    func dismissError() {
        errorMessage = nil
    }
    
    func currentSourceCityDate() -> Date {
        guard let sourceCity = sourceCity,
              let sourceTimezone = TimeZone(identifier: sourceCity.timezoneId) else {
            return Date()
        }
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = sourceTimezone
        let components = sourceCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        return Calendar.current.date(from: components) ?? Date()
    }
    
    func addCity(cityName: String, cityEn: String, timezoneId: String) {
        do {
            let exists = try cityService.hasCity(cityName: cityName, timezoneId: timezoneId)
            if !exists {
                try cityService.addCity(cityName: cityName, cityEn: cityEn, timezoneId: timezoneId)
            }
            // 重新加载城市列表
            let cities = try cityService.getAllCities()
            availableCities = cities
            if sourceCity == nil && !cities.isEmpty {
                sourceCity = cities.first
            }
            if targetCity == nil && cities.count > 1 {
                targetCity = cities[1]
            }
        } catch {
            errorMessage = String(localized: "converter.add.city.failed")
        }
    }
}
