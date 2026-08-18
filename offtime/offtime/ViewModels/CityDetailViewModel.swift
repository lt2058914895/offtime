import SwiftUI
import Combine
import SwiftData

// MARK: - CityDetailViewModel

@MainActor
final class CityDetailViewModel: ObservableObject {
    @Published var currentDate: Date = Date()
    @Published var localWorkStart: Int = 9
    @Published var localWorkEnd: Int = 18
    @Published var targetWorkStart: Int
    @Published var targetWorkEnd: Int
    @Published var use24Hour: Bool = true
    @Published var localTimezoneId: String = TimeZone.current.identifier

    let city: CityModel
    private let timezoneService = TimezoneService.shared

    init(city: CityModel) {
        self.city = city
        self.targetWorkStart = city.workStartHour
        self.targetWorkEnd = city.workEndHour
        self.localWorkStart = city.localWorkStart
        self.localWorkEnd = city.localWorkEnd
    }

    // MARK: - Time Display

    var cityTime: String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: city.timezoneId, date: currentDate) ?? "--:--"
        }
        return timezoneService.getLocalTime12(timezoneId: city.timezoneId, date: currentDate) ?? "--:--"
    }

    var localTime: String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: localTimezoneId, date: currentDate) ?? "--:--"
        }
        return timezoneService.getLocalTime12(timezoneId: localTimezoneId, date: currentDate) ?? "--:--"
    }

    var timeDifference: String {
        timezoneService.getTimeDifferenceBetween(sourceTimezoneId: localTimezoneId, targetTimezoneId: city.timezoneId, date: currentDate).offset
    }

    var isLocalCityDaytime: Bool {
        timezoneService.isDaytime(timezoneId: localTimezoneId, date: currentDate)
    }

    var isTargetCityDaytime: Bool {
        timezoneService.isDaytime(timezoneId: city.timezoneId, date: currentDate)
    }

    // MARK: - Timeline Data

    /// 本地当前时刻在 24 小时轴上的位置（含分钟小数）
    var localNowHour: Double {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: localTimezoneId) ?? .current
        let h = cal.component(.hour, from: currentDate)
        let m = cal.component(.minute, from: currentDate)
        return Double(h) + Double(m) / 60.0
    }

    /// 目标城市当前时刻在其自身 24 小时轴上的位置（含分钟小数）
    var targetNowHour: Double {
        guard let tz = TimeZone(identifier: city.timezoneId) else { return localNowHour }
        var cal = Calendar.current
        cal.timeZone = tz
        let h = cal.component(.hour, from: currentDate)
        let m = cal.component(.minute, from: currentDate)
        return Double(h) + Double(m) / 60.0
    }

    /// 本地工作时段（以本地 24 小时为轴）
    var localHourlyWorking: [Bool] {
        (0..<24).map { $0 >= localWorkStart && $0 < localWorkEnd }
    }

    /// 目标城市工作时段（以目标城市自身 24 小时为轴）
    var targetHourlyWorking: [Bool] {
        (0..<24).map { $0 >= targetWorkStart && $0 < targetWorkEnd }
    }

    /// 可联系重叠时段（以本地 24 小时为轴，双方均在各自工作时段内）
    var overlap: WorkingHoursOverlap {
        timezoneService.getWorkingHoursOverlap(
            timezoneId: city.timezoneId,
            date: currentDate,
            localTimezoneId: localTimezoneId,
            localWorkStart: localWorkStart,
            localWorkEnd: localWorkEnd,
            targetWorkStart: targetWorkStart,
            targetWorkEnd: targetWorkEnd
        )
    }

    var overlapSummary: String {
        let hourly = overlap.hourlyOverlap
        var ranges: [(Int, Int)] = []
        var rangeStart: Int? = nil
        for hour in 0..<24 {
            if hourly[hour] {
                if rangeStart == nil { rangeStart = hour }
            } else if let start = rangeStart {
                ranges.append((start, hour))
                rangeStart = nil
            }
        }
        if let start = rangeStart { ranges.append((start, 24)) }
        guard !ranges.isEmpty else { return String(localized: "detail.contactable.none") }
        let parts = ranges.map { String(format: "%02d:00–%02d:00", $0.0, $0.1) }
        let total = ranges.reduce(0) { $0 + ($1.1 - $1.0) }
        return parts.joined(separator: " ") + "（\(total)\(String(localized: "detail.hours"))）"
    }

    func saveWorkHours() {
        city.workStartHour = targetWorkStart
        city.workEndHour = targetWorkEnd
        city.localWorkStart = localWorkStart
        city.localWorkEnd = localWorkEnd
        try? CityService.shared.modelContainer.mainContext.save()
    }
}
