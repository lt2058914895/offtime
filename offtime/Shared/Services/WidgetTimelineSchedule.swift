import Foundation

/// 小组件时间线的规划：条目时间点 + 下次请求新时间线的期限。
///
/// 两条硬约束：
/// 1. **首个条目必须落在「当前这一分钟」**（不晚于 now）。WidgetKit 只会渲染时间点不晚于
///    当前时刻的条目；首个条目若在未来，刚添加/刚刷新的组件就没有可渲染的条目，
///    会停留在占位（redacted）状态，看起来就是「数据没有加载出来」。
///    旧实现用 `Calendar.date(bySetting: .second, value: 0, of: now)` 取整分钟，
///    该 API 是向后寻找**下一个**整分钟，因此首个条目会落在未来最多 60 秒处。
/// 2. 逐分钟条目只覆盖前几小时，之后退化为逐小时；因此必须给出 `reloadDate`，
///    让系统在分钟精度失效前重新请求时间线（`.atEnd` 会一直等到约 23 小时后才刷新，
///    期间组件的分钟显示会滞后，拿到过的旧数据也会一直沿用）。
enum WidgetTimelineSchedule {
    /// 逐分钟条目的分钟数（前 3 小时，保证分钟级刷新精度）
    static let minuteSpanCount = 3 * 60
    /// 之后按小时补齐的条目数（再覆盖 21 小时，整体约 24 小时）
    static let hourlySpanCount = 21

    static var entryCount: Int { minuteSpanCount + hourlySpanCount }

    struct Plan {
        /// 条目时间点，升序，首个条目为 now 所在的整分钟
        let dates: [Date]
        /// 逐分钟精度失效、需要重新请求时间线的期限
        let reloadDate: Date
    }

    static func plan(from now: Date, calendar: Calendar = .current) -> Plan {
        let start = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        ) ?? now

        var dates: [Date] = []
        dates.reserveCapacity(entryCount)

        for offset in 0..<minuteSpanCount {
            dates.append(start.addingTimeInterval(TimeInterval(offset * 60)))
        }

        let hourlyStart = start.addingTimeInterval(TimeInterval(minuteSpanCount * 60))
        for offset in 0..<hourlySpanCount {
            dates.append(hourlyStart.addingTimeInterval(TimeInterval(offset * 60 * 60)))
        }

        return Plan(dates: dates, reloadDate: hourlyStart)
    }
}
