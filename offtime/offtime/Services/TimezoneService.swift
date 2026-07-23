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
        
        let offset = timezone.secondsFromGMT() / 3600
        
        return TimezoneInfo(
            id: timezoneId,
            name: timezone.localizedName(for: .standard, locale: Locale.current) ?? timezoneId,
            offset: Double(offset * 3600)
        )
    }
    
    func getAllAvailableTimezones() -> [TimezoneInfo] {
        return TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            getTimezoneInfo(timezoneId: id)
        }
    }
}
