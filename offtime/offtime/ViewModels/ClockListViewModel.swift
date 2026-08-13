import Foundation
import Combine
import SwiftUI
import os

final class ClockListViewModel: ObservableObject {
    @Published var cities: [CityItem] = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    /// 管理模式下被勾选待删除的城市 ID
    @Published var selectedCityIds: Set<UUID> = []
    
    private let cityService = CityService.shared
    private let timezoneService = TimezoneService.shared
    private let appSettingService = AppSettingService.shared
    private let logger = Logger(subsystem: "lt.offtime", category: "ClockListViewModel")
    
    @Published var currentDate: Date = Date()
    private var timer: Timer?
    
    init() {
        startTimer()
        loadCities()
        loadUse24HourSetting()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startTimer() {
        // 已在运行则不重复启动，避免叠加多个 Timer
        guard timer == nil else { return }
        // UI 仅显示到分钟，无需每秒刷新。对齐到下一整分钟边界、之后每 60 秒触发一次，
        // 并设置 tolerance 让系统合并唤醒，显著降低耗电与发热。
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: Date(),
            matching: DateComponents(second: 0, nanosecond: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60)
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentDate = Date()
            }
        }
        timer.tolerance = 5
        timer.fireDate = nextMinute
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
    
    /// 静默重新加载城市列表（不触发 loading 态），用于导入后切回 Tab 的后台刷新
    func reloadCitiesSilently() {
        Task {
            do {
                let cities = try cityService.getAllCities()
                await MainActor.run {
                    self.cities = cities
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = String(localized: "db.read.failed")
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
                logger.error("加载 24 小时设置失败，使用默认值: \(error.localizedDescription)")
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
