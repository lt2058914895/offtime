import Foundation

final class TimezoneService {
    static let shared = TimezoneService()
    
    private let calendar = Calendar.current
    
    /// 线程安全的 TimeZone 缓存：避免每秒每城市重复调用 `TimeZone(identifier:)` 解析
    private let timezoneCache = NSCache<NSString, NSTimeZone>()
    /// 线程安全的 DateFormatter 缓存：key = "timezoneId|dateFormat|localeIdentifier"
    private let formatterCache = NSCache<NSString, DateFormatter>()
    
    private init() {
        // 缓存成本按对象数量计，时钟类 App 实际涉及的时区有限（通常 < 50）
        timezoneCache.countLimit = 64
        formatterCache.countLimit = 256
    }
    
    // MARK: - Private Helpers
    
    /// 带缓存的 TimeZone 查询：miss 时解析并存入缓存
    private func timezone(for id: String) -> TimeZone? {
        if let cached = timezoneCache.object(forKey: id as NSString) {
            return cached as TimeZone
        }
        guard let tz = TimeZone(identifier: id) else { return nil }
        timezoneCache.setObject(tz as NSTimeZone, forKey: id as NSString)
        return tz
    }
    
    /// 创建/复用线程安全的 DateFormatter（缓存键含时区+格式+locale，locale 变更会自动 miss 重建）
    private func makeFormatter(timezone: TimeZone, dateFormat: String, locale: Locale = .current) -> DateFormatter {
        let cacheKey = "\(timezone.identifier)|\(dateFormat)|\(locale.identifier)" as NSString
        if let cached = formatterCache.object(forKey: cacheKey) {
            return cached
        }
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = dateFormat
        formatter.locale = locale
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        formatterCache.setObject(formatter, forKey: cacheKey)
        return formatter
    }
    
    // MARK: - Time Formatting
    
    func getLocalTime24(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "HH:mm").string(from: date)
    }
    
    func getLocalTime12(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "h:mm a").string(from: date)
    }
    
    func getLocalDate(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "yyyy-MM-dd").string(from: date)
    }
    
    func getLocalWeekday(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "EEEE").string(from: date)
    }
    
    func getLocalDateTime(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "yyyy-MM-dd HH:mm").string(from: date)
    }
    
    // MARK: - Daytime Detection
    
    func isDaytime(timezoneId: String, date: Date = Date()) -> Bool {
        guard let timezone = timezone(for: timezoneId) else { return true }
        let hourStr = makeFormatter(timezone: timezone, dateFormat: "HH").string(from: date)
        if let hour = Int(hourStr) {
            return hour >= 6 && hour < 18
        }
        return true
    }
    
    // MARK: - Time Difference
    
    func getTimeDifference(timezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let targetTimezone = timezone(for: timezoneId) else {
            return ("", nil)
        }
        
        let localTimezone = TimeZone.current
        let targetOffset = targetTimezone.secondsFromGMT(for: date)
        let localOffset = localTimezone.secondsFromGMT(for: date)
        let diffHours = Double(targetOffset - localOffset) / 3600
        
        return formatTimeDifference(diffHours: diffHours)
    }
    
    func getTimeDifferenceBetween(sourceTimezoneId: String, targetTimezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let sourceTimezone = timezone(for: sourceTimezoneId),
              let targetTimezone = timezone(for: targetTimezoneId) else {
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
                crossDay = String(localized: "clock.tomorrow")
            }
        } else {
            offsetStr = "\(Int(diffHours))h"
            if diffHours <= -24 {
                crossDay = String(localized: "clock.yesterday")
            }
        }
        
        return (offsetStr, crossDay)
    }
    
    // MARK: - Time Conversion
    
    func convertTime(sourceTimezoneId: String, targetTimezoneId: String, sourceDate: Date) -> Date? {
        guard let sourceTimezone = timezone(for: sourceTimezoneId),
              let targetTimezone = timezone(for: targetTimezoneId) else {
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
        guard let timezone = timezone(for: timezoneId) else {
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
        guard let timezone = timezone(for: timezoneId) else {
            return nil
        }
        
        if timezone.isDaylightSavingTime(for: date) {
            return String(localized: "clock.dst.summer")
        }
        
        if timezone.nextDaylightSavingTimeTransition(after: date) != nil {
            return String(localized: "clock.dst.winter")
        }
        
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: date) ?? date
        if timezone.nextDaylightSavingTimeTransition(after: oneYearAgo) != nil {
            return String(localized: "clock.dst.winter")
        }
        
        return nil
    }
    
    func getAllAvailableTimezones() -> [TimezoneInfo] {
        return TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            getTimezoneInfo(timezoneId: id)
        }
    }
}
