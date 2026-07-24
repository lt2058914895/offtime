import Foundation
import Combine
import SwiftUI

final class ClockListViewModel: ObservableObject {
    @Published var cities: [CityItem] = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = true
    
    private let cityService = CityService.shared
    private let timezoneService = TimezoneService.shared
    private let appSettingService = AppSettingService.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published var currentDate: Date = Date()
    private var timer: Timer?
    
    init() {
        startTimer()
        loadCities()
        loadUse24HourSetting()
        
        $use24Hour
            .dropFirst()
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentDate = Date()
            }
        }
    }
    
    func loadCities() {
        viewState = .loading
        
        Task {
            do {
                let cities = try cityService.getAllCities()
                await MainActor.run {
                    self.cities = cities
                    self.viewState = .idle
                }
            } catch {
                await MainActor.run {
                    self.viewState = .failure("数据库读取失败")
                    self.errorMessage = "数据库读取失败，请尝试重启App"
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
    
    func addCity(cityName: String, cityEn: String, timezoneId: String) {
        Task {
            do {
                try cityService.addCity(cityName: cityName, cityEn: cityEn, timezoneId: timezoneId)
                await MainActor.run {
                    self.loadCities()
                }
            } catch CityError.alreadyExists {
                await MainActor.run {
                    self.errorMessage = "该城市已存在"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "添加城市失败"
                }
            }
        }
    }
    
    func deleteCity(id: UUID) {
        Task {
            do {
                try cityService.deleteCity(id: id)
                await MainActor.run {
                    self.loadCities()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "删除城市失败"
                }
            }
        }
    }
    
    func reorderCities(_ cities: [CityItem]) {
        Task {
            do {
                try cityService.reorderCities(cities)
                await MainActor.run {
                    self.cities = cities
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "排序失败"
                }
            }
        }
    }
    
    func getLocalTime(city: CityItem) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: city.timezoneId, date: currentDate) ?? "时间解析失败"
        } else {
            return timezoneService.getLocalTime12(timezoneId: city.timezoneId, date: currentDate) ?? "时间解析失败"
        }
    }
    
    func getLocalDate(city: CityItem) -> String {
        return timezoneService.getLocalDate(timezoneId: city.timezoneId, date: currentDate) ?? "日期解析失败"
    }
    
    func getRelativeDate(city: CityItem) -> String {
        let targetDateStr = timezoneService.getLocalDate(timezoneId: city.timezoneId, date: currentDate) ?? ""
        let localDateStr = timezoneService.getLocalDate(timezoneId: TimeZone.current.identifier, date: currentDate) ?? ""
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let targetDate = formatter.date(from: targetDateStr),
              let localDate = formatter.date(from: localDateStr) else {
            return targetDateStr
        }
        
        let diff = Calendar.current.dateComponents([.day], from: localDate, to: targetDate).day ?? 0
        
        switch diff {
        case 0: return "今天"
        case 1: return "明天"
        case -1: return "昨天"
        default: return targetDateStr
        }
    }
    
    func getTimeDifference(city: CityItem) -> (offset: String, crossDay: String?) {
        return timezoneService.getTimeDifference(timezoneId: city.timezoneId, date: currentDate)
    }
    
    func isDaytime(city: CityItem) -> Bool {
        return timezoneService.isDaytime(timezoneId: city.timezoneId, date: currentDate)
    }
    
    func getDSTStatus(city: CityItem) -> String? {
        return timezoneService.getDSTStatus(timezoneId: city.timezoneId, date: currentDate)
    }
    
    func copyTimeText(city: CityItem) -> String {
        let time = getLocalTime(city: city)
        let date = getLocalDate(city: city)
        return "\(city.cityName) \(date) \(time)"
    }
    
    func dismissError() {
        errorMessage = nil
    }
}
