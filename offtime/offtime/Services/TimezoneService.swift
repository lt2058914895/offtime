import Foundation

final class TimezoneService {
    static let shared = TimezoneService()
    
    private let calendar = Calendar.current
    
    private init() {}
    
    // MARK: - Private Helpers
    
    /// 创建线程安全的 DateFormatter（每次调用创建新实例，避免数据竞争）
    private func makeFormatter(timezone: TimeZone, dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = dateFormat
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }
    
    // MARK: - Time Formatting
    
    func getLocalTime24(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "HH:mm").string(from: date)
    }
    
    func getLocalTime12(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "h:mm a").string(from: date)
    }
    
    func getLocalDate(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "yyyy-MM-dd").string(from: date)
    }
    
    func getLocalDateTime(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "yyyy-MM-dd HH:mm").string(from: date)
    }
    
    // MARK: - Daytime Detection
    
    func isDaytime(timezoneId: String, date: Date = Date()) -> Bool {
        guard let timezone = TimeZone(identifier: timezoneId) else { return true }
        let hourStr = makeFormatter(timezone: timezone, dateFormat: "HH").string(from: date)
        if let hour = Int(hourStr) {
            return hour >= 6 && hour < 18
        }
        return true
    }
    
    // MARK: - Time Difference
    
    func getTimeDifference(timezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let targetTimezone = TimeZone(identifier: timezoneId) else {
            return ("", nil)
        }
        
        let localTimezone = TimeZone.current
        let targetOffset = targetTimezone.secondsFromGMT(for: date)
        let localOffset = localTimezone.secondsFromGMT(for: date)
        let diffHours = Double(targetOffset - localOffset) / 3600
        
        return formatTimeDifference(diffHours: diffHours)
    }
    
    func getTimeDifferenceBetween(sourceTimezoneId: String, targetTimezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let sourceTimezone = TimeZone(identifier: sourceTimezoneId),
              let targetTimezone = TimeZone(identifier: targetTimezoneId) else {
            return ("", nil)
        }
        
        let sourceOffset = sourceTimezone.secondsFromGMT(for: date)
        let targetOffset = targetTimezone.secondsFromGMT(for: date)
        let diffHours = Double(targetOffset - sourceOffset) / 3600
        
        return formatTimeDifference(diffHours: diffHours)
    }
    
    private func formatTimeDifference(diffHours: Double) -> (offset: String, crossDay: String?) {
        var offsetStr: String
        var crossDay: String?
        
        if diffHours == 0 {
            offsetStr = "0h"
        } else if diffHours > 0 {
            offsetStr = "+\(Int(diffHours))h"
            if diffHours >= 24 {
                crossDay = "明日"
            }
        } else {
            offsetStr = "\(Int(diffHours))h"
            if diffHours <= -24 {
                crossDay = "昨日"
            }
        }
        
        return (offsetStr, crossDay)
    }
    
    // MARK: - Time Conversion
    
    func convertTime(sourceTimezoneId: String, targetTimezoneId: String, sourceDate: Date) -> Date? {
        guard let sourceTimezone = TimeZone(identifier: sourceTimezoneId),
              let targetTimezone = TimeZone(identifier: targetTimezoneId) else {
            return nil
        }
        
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = sourceTimezone
        
        var targetCalendar = Calendar.current
        targetCalendar.timeZone = targetTimezone
        
        let components = sourceCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: sourceDate)
        return targetCalendar.date(from: components)
    }
    
    // MARK: - Timezone Info
    
    func getTimezoneInfo(timezoneId: String) -> TimezoneInfo? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        let offset = timezone.secondsFromGMT(for: Date()) / 3600
        
        return TimezoneInfo(
            id: timezoneId,
            name: timezone.localizedName(for: .standard, locale: Locale.current) ?? timezoneId,
            offset: Double(offset * 3600)
        )
    }
    
    /// 获取城市的夏令时状态
    /// - Returns: "夏令时" / "冬令时" / nil（不使用夏令时的地区返回nil）
    func getDSTStatus(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        if timezone.isDaylightSavingTime(for: date) {
            return "夏令时"
        }
        
        if timezone.nextDaylightSavingTimeTransition(after: date) != nil {
            return "冬令时"
        }
        
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: date) ?? date
        if timezone.nextDaylightSavingTimeTransition(after: oneYearAgo) != nil {
            return "冬令时"
        }
        
        return nil
    }
    
    func getAllAvailableTimezones() -> [TimezoneInfo] {
        return TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            getTimezoneInfo(timezoneId: id)
        }
    }
}