import Foundation

/// 用户可见的日期统一使用斜杠分隔的数字年月日，不随中英文环境切换格式。
enum DateDisplayFormat {
    static let yearMonthDay = "yyyy/MM/dd"
    static let yearMonthDayAndTime = "yyyy/MM/dd HH:mm"

    private static let formatterCache = NSCache<NSString, DateFormatter>()
    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    static func date(_ date: Date, timezone: TimeZone) -> String {
        let cacheKey = timezone.identifier as NSString
        if let formatter = formatterCache.object(forKey: cacheKey) {
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timezone
        formatter.dateFormat = yearMonthDay
        formatterCache.setObject(formatter, forKey: cacheKey)
        return formatter.string(from: date)
    }

    /// 星期固定使用紧凑的“周一…周日”，不随系统语言变成“星期五”或“Friday”。
    static func weekday(_ date: Date, timezone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let weekday = calendar.component(.weekday, from: date)
        guard weekdayNames.indices.contains(weekday - 1) else { return "" }
        return weekdayNames[weekday - 1]
    }

    static func dateWithWeekday(_ date: Date, timezone: TimeZone) -> String {
        "\(self.date(date, timezone: timezone)) \(weekday(date, timezone: timezone))"
            .trimmingCharacters(in: .whitespaces)
    }

    /// 会议时间范围。日期始终使用开始日，结束时间跨天时增加相对日标记。
    static func timeRange(
        start: Date,
        end: Date,
        timezone: TimeZone,
        use24Hour: Bool? = nil,
        locale: Locale = .current
    ) -> String {
        let format: String
        if let use24Hour {
            format = use24Hour ? "HH:mm" : "h:mm a"
        } else {
            format = DateFormatter.dateFormat(
                fromTemplate: "jmm",
                options: 0,
                locale: locale
            ) ?? "HH:mm"
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timezone
        formatter.dateFormat = format

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let dayOffset = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        let endText = formatter.string(from: end)

        guard dayOffset > 0 else {
            return "\(formatter.string(from: start))–\(endText)"
        }

        let marker: String
        let isChinese = locale.language.languageCode?.identifier == "zh"
        if dayOffset == 1 {
            marker = isChinese ? "次日" : "next day"
        } else {
            marker = isChinese ? "\(dayOffset)天后" : "\(dayOffset) days later"
        }
        return "\(formatter.string(from: start))–\(marker) \(endText)"
    }
}
