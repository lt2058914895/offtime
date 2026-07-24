import Foundation
import Combine

final class ConverterViewModel: ObservableObject {
    @Published var sourceCity: CityItem?
    @Published var targetCity: CityItem?
    @Published var sourceDate: Date = Date()
    
    @Published var resultTime: String = ""
    @Published var resultDate: String = ""
    @Published var timeDifference: String = ""
    @Published var crossDay: String?
    
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = true
    
    private let timezoneService = TimezoneService.shared
    private let appSettingService = AppSettingService.shared
    private let cityService = CityService.shared
    
    @Published var availableCities: [CityItem] = []
    @Published var isSwapping: Bool = false
    
    init() {
        loadCities()
        loadUse24HourSetting()
        
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
    
    private func loadCities() {
        Task {
            do {
                let cities = try cityService.getAllCities()
                await MainActor.run {
                    self.availableCities = cities
                    
                    if self.sourceCity == nil && !cities.isEmpty {
                        self.sourceCity = cities.first
                    }
                    if self.targetCity == nil && cities.count > 1 {
                        self.targetCity = cities[1]
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载城市失败"
                }
            }
        }
    }
    
    private func loadUse24HourSetting() {
        Task {
            do {
                let settings = try appSettingService.loadSettings()
                await MainActor.run {
                    self.use24Hour = settings.use24Hour
                }
            } catch {
                // 使用默认值
            }
        }
    }
    
    func refreshFormat() {
        convertTime(source: sourceCity, target: targetCity, date: sourceDate)
    }
    
    private func convertTime(source: CityItem?, target: CityItem?, date: Date) {
        guard let source = source, let target = target else {
            resultTime = "请选择城市"
            resultDate = ""
            timeDifference = ""
            crossDay = nil
            return
        }
        
        guard let sourceTimezone = TimeZone(identifier: source.timezoneId),
              let targetTimezone = TimeZone(identifier: target.timezoneId) else {
            resultTime = "时区解析失败"
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
            resultTime = "时间转换失败"
            resultDate = ""
            timeDifference = ""
            crossDay = nil
            return
        }
        
        // 用目标时区格式化结果
        if use24Hour {
            resultTime = timezoneService.getLocalTime24(timezoneId: target.timezoneId, date: absoluteDate) ?? "时间解析失败"
        } else {
            resultTime = timezoneService.getLocalTime12(timezoneId: target.timezoneId, date: absoluteDate) ?? "时间解析失败"
        }
        resultDate = timezoneService.getLocalDate(timezoneId: target.timezoneId, date: absoluteDate) ?? "日期解析失败"
        
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
    
    func swapCities() {
        isSwapping = true
        let temp = sourceCity
        sourceCity = targetCity
        targetCity = temp
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
        Task {
            do {
                let exists = try cityService.hasCity(cityName: cityName)
                if !exists {
                    try cityService.addCity(cityName: cityName, cityEn: cityEn, timezoneId: timezoneId)
                }
                // 重新加载城市列表
                let cities = try cityService.getAllCities()
                await MainActor.run {
                    self.availableCities = cities
                    if self.sourceCity == nil && !cities.isEmpty {
                        self.sourceCity = cities.first
                    }
                    if self.targetCity == nil && cities.count > 1 {
                        self.targetCity = cities[1]
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "添加城市失败"
                }
            }
        }
    }
}
