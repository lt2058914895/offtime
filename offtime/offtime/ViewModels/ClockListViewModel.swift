import Foundation
import Combine
import SwiftUI
import SwiftData
import os

@MainActor
final class ClockListViewModel: ObservableObject {
    @Published var cities: [CityModel] = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    /// 管理模式下被勾选待删除的城市 ID
    @Published var selectedCityIds: Set<UUID> = []
    
    private let cityService = CityService.shared
    private let timezoneService = TimezoneService.shared
    private let logger = Logger(subsystem: "lt.offtime", category: "ClockListViewModel")
    
    @Published var currentDate: Date = Date()
    private var timer: Timer?
    
    init() {
        startTimer()
        loadCities()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startTimer() {
        guard timer == nil else { return }
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
    
    func pauseTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func resumeTimer() {
        currentDate = Date()
        startTimer()
    }
    
    func loadCities() {
        viewState = .loading
        do {
            cities = try cityService.getAllCities()
            viewState = .idle
        } catch {
            viewState = .failure(String(localized: "db.read.failed"))
            errorMessage = String(localized: "db.read.failed.restart")
        }
    }
    
    /// 静默重新加载城市列表
    func reloadCitiesSilently() {
        do {
            cities = try cityService.getAllCities()
        } catch {
            errorMessage = String(localized: "db.read.failed")
        }
    }
    
    func addCity(cityName: String, cityEn: String, timezoneId: String) {
        do {
            try cityService.addCity(cityName: cityName, cityEn: cityEn, timezoneId: timezoneId)
            loadCities()
            Haptics.success()
        } catch CityError.alreadyExists {
            errorMessage = String(localized: "clock.city.exists")
            Haptics.warning()
        } catch {
            errorMessage = String(localized: "clock.add.failed")
            Haptics.error()
        }
    }
    
    func deleteCity(id: UUID) {
        do {
            try cityService.deleteCity(id: id)
            loadCities()
            Haptics.medium()
        } catch {
            errorMessage = String(localized: "clock.delete.failed")
            Haptics.error()
        }
    }
    
    // MARK: - 管理模式批量选择
    
    var allSelected: Bool {
        !cities.isEmpty && selectedCityIds.count == cities.count
    }
    
    func toggleSelection(id: UUID) {
        if selectedCityIds.contains(id) {
            selectedCityIds.remove(id)
        } else {
            selectedCityIds.insert(id)
        }
        Haptics.selection()
    }
    
    func selectAllCities() {
        selectedCityIds = Set(cities.map { $0.id })
    }
    
    func clearSelection() {
        selectedCityIds.removeAll()
    }
    
    func toggleSelectAll() {
        if allSelected {
            clearSelection()
        } else {
            selectAllCities()
        }
    }
    
    func deleteSelectedCities() {
        let ids = Array(selectedCityIds)
        guard !ids.isEmpty else { return }
        do {
            try cityService.deleteCities(ids: ids)
            selectedCityIds.removeAll()
            loadCities()
            Haptics.medium()
        } catch {
            errorMessage = String(localized: "clock.delete.failed")
            loadCities()
            Haptics.error()
        }
    }
    
    func reorderCities(_ cities: [CityModel]) {
        do {
            try cityService.reorderCities(cities)
            self.cities = cities
            Haptics.light()
        } catch {
            errorMessage = String(localized: "clock.reorder.failed")
        }
    }
    
    // MARK: - 时间格式化（委托 TimezoneService）
    
    func getLocalTime(city: CityModel) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: city.timezoneId, date: currentDate) ?? String(localized: "clock.time.parse.failed")
        } else {
            return timezoneService.getLocalTime12(timezoneId: city.timezoneId, date: currentDate) ?? String(localized: "clock.time.parse.failed")
        }
    }
    
    func getLocalDate(city: CityModel) -> String {
        return timezoneService.getLocalDate(timezoneId: city.timezoneId, date: currentDate) ?? String(localized: "clock.date.parse.failed")
    }
    
    func getLocalWeekday(city: CityModel) -> String {
        return timezoneService.getLocalWeekday(timezoneId: city.timezoneId, date: currentDate) ?? ""
    }
    
    func getTimeDifference(city: CityModel) -> (offset: String, crossDay: String?) {
        return timezoneService.getTimeDifference(timezoneId: city.timezoneId, date: currentDate)
    }
    
    func isDaytime(city: CityModel) -> Bool {
        return timezoneService.isDaytime(timezoneId: city.timezoneId, date: currentDate)
    }
    
    func getDSTStatus(city: CityModel) -> String? {
        return timezoneService.getDSTStatus(timezoneId: city.timezoneId, date: currentDate)
    }
    
    func copyTimeText(city: CityModel) -> String {
        let time = getLocalTime(city: city)
        let date = getLocalDate(city: city)
        return "\(city.cityName) \(date) \(time)"
    }
    
    func dismissError() {
        errorMessage = nil
    }
}
