import Foundation
import Combine
import SwiftUI

final class ClockListViewModel: ObservableObject {
    @Published var cities: [CityItem] = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = Locale.systemUses24Hour
    /// 管理模式下被勾选待删除的城市 ID
    @Published var selectedCityIds: Set<UUID> = []
    
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
        // 已在运行则不重复启动，避免叠加多个 Timer
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentDate = Date()
            }
        }
    }
    
    /// 暂停定时器（App 进入后台时调用），停止每秒的时区重算，省电防发热
    func pauseTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    /// 恢复定时器并立即刷新一次时间，避免从后台返回后短暂显示过期时间
    func resumeTimer() {
        currentDate = Date()
        startTimer()
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
                    self.viewState = .failure(String(localized: "db.read.failed"))
                    self.errorMessage = String(localized: "db.read.failed.restart")
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
                    self.errorMessage = String(localized: "clock.city.exists")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = String(localized: "clock.add.failed")
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
                    self.errorMessage = String(localized: "clock.delete.failed")
                }
            }
        }
    }

    // MARK: - 管理模式批量选择

    /// 是否所有城市均被选中（列表非空时才有意义）
    var allSelected: Bool {
        !cities.isEmpty && selectedCityIds.count == cities.count
    }

    func toggleSelection(id: UUID) {
        if selectedCityIds.contains(id) {
            selectedCityIds.remove(id)
        } else {
            selectedCityIds.insert(id)
        }
    }

    /// 全选当前所有城市
    func selectAllCities() {
        selectedCityIds = Set(cities.map { $0.id })
    }

    /// 清空所有勾选
    func clearSelection() {
        selectedCityIds.removeAll()
    }

    /// 全选 / 取消全选切换
    func toggleSelectAll() {
        if allSelected {
            clearSelection()
        } else {
            selectAllCities()
        }
    }

    /// 删除所有被勾选的城市（事务性，失败整体回滚）
    func deleteSelectedCities() {
        let ids = Array(selectedCityIds)
        guard !ids.isEmpty else { return }
        Task {
            do {
                try cityService.deleteCities(ids: ids)
                await MainActor.run {
                    self.selectedCityIds.removeAll()
                    self.loadCities()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = String(localized: "clock.delete.failed")
                    self.loadCities()
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
                    self.errorMessage = String(localized: "clock.reorder.failed")
                }
            }
        }
    }
    
    func getLocalTime(city: CityItem) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: city.timezoneId, date: currentDate) ?? String(localized: "clock.time.parse.failed")
        } else {
            return timezoneService.getLocalTime12(timezoneId: city.timezoneId, date: currentDate) ?? String(localized: "clock.time.parse.failed")
        }
    }
    
    func getLocalDate(city: CityItem) -> String {
        return timezoneService.getLocalDate(timezoneId: city.timezoneId, date: currentDate) ?? String(localized: "clock.date.parse.failed")
    }
    
    func getLocalWeekday(city: CityItem) -> String {
        return timezoneService.getLocalWeekday(timezoneId: city.timezoneId, date: currentDate) ?? ""
    }
    
    func getRelativeDate(city: CityItem) -> String {
        guard let timezone = TimeZone(identifier: city.timezoneId) else {
            return getLocalDate(city: city)
        }
        
        let now = currentDate
        let calendar = Calendar.current
        
        // 获取目标时区的"今天"日期组件
        var targetCalendar = calendar
        targetCalendar.timeZone = timezone
        let targetDay = targetCalendar.dateComponents([.year, .month, .day], from: now)
        
        // 获取本地时区的"今天"日期组件
        let localDay = calendar.dateComponents([.year, .month, .day], from: now)
        
        // 比较日期差异
        let targetDate = calendar.date(from: targetDay)
        let localDate = calendar.date(from: localDay)
        
        guard let t = targetDate, let l = localDate else {
            return getLocalDate(city: city)
        }
        
        let diff = calendar.dateComponents([.day], from: l, to: t).day ?? 0
        
        switch diff {
        case 0: return String(localized: "clock.today")
        case 1: return String(localized: "clock.tomorrow")
        case -1: return String(localized: "clock.yesterday")
        default: return getLocalDate(city: city)
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
