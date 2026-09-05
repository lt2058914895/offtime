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
        // 不强制 amSymbol/pmSymbol：让 formatter 按当前 locale 自动本地化
        // （中文=上午/下午、日文=午前/午後、韩文=오전/오후、英文=AM/PM）
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
        return makeFormatter(timezone: timezone, dateFormat: "yyyy/MM/dd").string(from: date)
    }
    
    func getLocalWeekday(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "EEE").string(from: date)
    }
    
    func getLocalDateTime(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        return makeFormatter(timezone: timezone, dateFormat: "yyyy-MM-dd HH:mm").string(from: date)
    }

    func getLocalizedTime(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        let format = DateFormatter.dateFormat(
            fromTemplate: "jmm",
            options: 0,
            locale: Locale.current
        ) ?? "HH:mm"
        return makeFormatter(timezone: timezone, dateFormat: format).string(from: date)
    }

    func getMonthDay(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        let format = DateFormatter.dateFormat(
            fromTemplate: "MMEd",
            options: 0,
            locale: Locale.current
        ) ?? "MM/dd"
        return makeFormatter(timezone: timezone, dateFormat: format).string(from: date)
    }

    func getUTCText(timezoneId: String) -> String? {
        guard let timezone = timezone(for: timezoneId) else { return nil }
        let seconds = timezone.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        if minutes == 0 {
            return String(format: "UTC%+d", hours)
        }
        return String(format: "UTC%+d:%02d", hours, minutes)
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
        // 以分钟为单位保留半小时等非整数时区精度
        let totalMinutes = (targetOffset - localOffset) / 60
        let crossDay = crossDayLabel(localTimezone: localTimezone, targetTimezone: targetTimezone, date: date)

        return (formatTimeDifference(totalMinutes: totalMinutes), crossDay)
    }

    func getTimeDifferenceBetween(sourceTimezoneId: String, targetTimezoneId: String, date: Date = Date()) -> (offset: String, crossDay: String?) {
        guard let sourceTimezone = timezone(for: sourceTimezoneId),
              let targetTimezone = timezone(for: targetTimezoneId) else {
            return ("", nil)
        }

        let sourceOffset = sourceTimezone.secondsFromGMT(for: date)
        let targetOffset = targetTimezone.secondsFromGMT(for: date)
        let totalMinutes = (targetOffset - sourceOffset) / 60
        let crossDay = crossDayLabel(localTimezone: sourceTimezone, targetTimezone: targetTimezone, date: date)

        return (formatTimeDifference(totalMinutes: totalMinutes), crossDay)
    }

    /// 拼接时差字符串：保留半小时精度，整数时区不带冗余 0m。
    /// - Parameter totalMinutes: 目标时区相对源时区的偏移分钟数（正=超前，负=滞后）
    private func formatTimeDifference(totalMinutes: Int) -> String {
        if totalMinutes == 0 {
            return "0h"
        }

        let sign = totalMinutes > 0 ? "+" : "-"
        let absolute = abs(totalMinutes)
        let hours = absolute / 60
        let minutes = absolute % 60
        if minutes == 0 {
            return "\(sign)\(hours)h"
        }
        return "\(sign)\(hours)h\(minutes)m"
    }

    /// 用日历日比较判跨天：比较 date 时刻在源/目标时区下所处的「日序」，
    /// 避免用小时差推断在边界附近（如 +23h 但已跨日）误判。
    private func crossDayLabel(localTimezone: TimeZone, targetTimezone: TimeZone, date: Date) -> String? {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localTimezone
        var targetCalendar = Calendar(identifier: .gregorian)
        targetCalendar.timeZone = targetTimezone

        let localDay = localCalendar.dateComponents([.year, .month, .day], from: date)
        let targetDay = targetCalendar.dateComponents([.year, .month, .day], from: date)

        guard let localDayValue = calendarDayValue(localDay),
              let targetDayValue = calendarDayValue(targetDay) else { return nil }

        if targetDayValue > localDayValue {
            return String(localized: "clock.tomorrow")
        } else if targetDayValue < localDayValue {
            return String(localized: "clock.yesterday")
        }
        return nil
    }

    private func calendarDayValue(_ components: DateComponents) -> Int? {
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return nil }
        return year * 10_000 + month * 100 + day
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
    /// - Returns: "夏令时" / nil（不使用夏令时或当前处于标准时间的地区返回nil）
    func getDSTStatus(timezoneId: String, date: Date = Date()) -> String? {
        guard let timezone = timezone(for: timezoneId) else {
            return nil
        }
        
        if timezone.isDaylightSavingTime(for: date) {
            return String(localized: "clock.dst.summer")
        }
        
        return nil
    }
}
