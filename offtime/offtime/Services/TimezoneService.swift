import Foundation

final class TimezoneService {
    static let shared = TimezoneService()
    
    private let dateFormatter = DateFormatter()
    private let calendar = Calendar.current
    
    private init() {}
    
    func getLocalTime(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "HH:mm"
        
        return dateFormatter.string(from: date)
    }
    
    func getLocalTime24(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "HH:mm"
        
        return dateFormatter.string(from: date)
    }
    
    func getLocalTime12(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "h:mm a"
        dateFormatter.amSymbol = "AM"
        dateFormatter.pmSymbol = "PM"
        
        return dateFormatter.string(from: date)
    }
    
    func getLocalDate(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return dateFormatter.string(from: date)
    }
    
    func getLocalDateTime(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return nil
        }
        
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        return dateFormatter.string(from: date)
    }
    
    func isDaytime(timezoneId: String, date: Date = Date()) -> Bool {
        guard let timezone = TimeZone(identifier: timezoneId) else {
            return true
        }
        
        dateFormatter.timeZone = timezone
        dateFormatter.dateFormat = "HH"
        
        if let hour = Int(dateFormatter.string(from: date)) {
            return hour >= 6 && hour < 18
        }
        
        return true
    }
    
    func getTimeDifference(timezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let targetTimezone = TimeZone(identifier: timezoneId) else {
            return ("", nil)
        }
        
        let localTimezone = TimeZone.current
        let targetOffset = targetTimezone.secondsFromGMT(for: date)
        let localOffset = localTimezone.secondsFromGMT(for: date)
        
        let diffSeconds = targetOffset - localOffset
        let diffHours = Double(diffSeconds) / 3600
        
        return formatTimeDifference(diffHours: diffHours)
    }
    
    func getTimeDifferenceBetween(sourceTimezoneId: String, targetTimezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let sourceTimezone = TimeZone(identifier: sourceTimezoneId),
              let targetTimezone = TimeZone(identifier: targetTimezoneId) else {
            return ("", nil)
        }
        
        let sourceOffset = sourceTimezone.secondsFromGMT(for: date)
        let targetOffset = targetTimezone.secondsFromGMT(for: date)
        
        let diffSeconds = targetOffset - sourceOffset
        let diffHours = Double(diffSeconds) / 3600
        
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
    
    func convertTime(sourceTimezoneId: String, targetTimezoneId: String, sourceDate: Date) -> Date? {
        guard let sourceTimezone = TimeZone(identifier: sourceTimezoneId),
              let targetTimezone = TimeZone(identifier: targetTimezoneId) else {
            return nil
        }
        
        // 使用源时区的日历获取时间组件
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = sourceTimezone
        
        // 使用目标时区的日历
        var targetCalendar = Calendar.current
        targetCalendar.timeZone = targetTimezone
        
        // 获取源日期在源时区的时间组件（年、月、日、时、分）
        let components = sourceCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: sourceDate)
        
        // 用目标时区的日历重新创建日期
        return targetCalendar.date(from: components)
    }
    
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
        
        // 当前是否处于夏令时
        if timezone.isDaylightSavingTime(for: date) {
            return "夏令时"
        }
        
        // 当前不在夏令时，判断该时区是否使用夏令时制度
        // 检查未来是否有夏令时切换点
        if timezone.nextDaylightSavingTimeTransition(after: date) != nil {
            return "冬令时"
        }
        
        // 检查过去一年内是否有夏令时切换点（处理年末边界情况）
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: date) ?? date
        if timezone.nextDaylightSavingTimeTransition(after: oneYearAgo) != nil {
            return "冬令时"
        }
        
        // 该时区不使用夏令时
        return nil
    }
    
    func getAllAvailableTimezones() -> [TimezoneInfo] {
        return TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            getTimezoneInfo(timezoneId: id)
        }
    }
}
