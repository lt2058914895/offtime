import Foundation

/// 小组件时间线的规划：条目时间点 + 下次请求新时间线的期限。
///
/// 四条硬约束：
/// 1. **首个条目就是请求时刻 `now`**（不晚于 now）。WidgetKit 只会渲染时间点不晚于当前时刻的
///    条目；首个条目若落在未来，刚添加 / 刚刷新的组件就没有可渲染条目，会停留在占位
///    （redacted）状态，看起来就是「数据没有加载出来」。
///    更早的实现用 `Calendar.date(bySetting: .second, value: 0, of: now)` 取整分钟，该 API
///    会向后寻找**下一个**整分钟，首个条目因此落在未来最多 60 秒处；改成「当前分钟起点」后
///    仍依赖取整结果，这里直接用 `now`，从构造上保证首条目永远可用。
/// 2. **条目数量必须克制**。WidgetKit 会为时间线里的**每一条 entry** 渲染并归档一份视图，
///    归档体积 ≈ 条目数 × 单个视图的复杂度：逐分钟 180 条 + 逐小时 21 条 = 201 条时，
///    大尺寸（一行一个城市，最多 6 行，节点最多）的归档会明显大于小/中尺寸，
///    一旦超出系统给组件归档/缓存的体积与内存预算，这份时间线就用不了，
///    组件会一直停在占位（redacted）状态——表现就是小/中尺寸正常、大尺寸「数据一直加载不出来」。
///    因此逐分钟只覆盖 1 小时、逐小时再补 12 小时，共 72 条。
/// 3. 逐分钟精度只覆盖前 1 小时，之后退化为逐小时；因此必须给出 `reloadDate`，
///    让系统在分钟精度失效前重新请求时间线（`.atEnd` 会一直等到约 13 小时后才刷新，
///    期间分钟的显示会滞后）。
/// 4. 组件还读不到数据时不能等满 1 小时：那种情况下用短间隔重试，
///    否则「组件刚添加、App 还没发布过城市」会长时间停在空态，用户以为数据加载不出来。
enum WidgetTimelineSchedule {
    /// 逐分钟条目的分钟数（前 1 小时，保证分钟级刷新精度）。
    /// 数量直接决定归档体积，见文件头第 2 条：不要为了「少刷新几次」把它调大。
    static let minuteSpanCount = 60
    /// 之后按小时补齐的条目数（再覆盖 12 小时；正常情况下 1 小时后就会重新请求时间线，
    /// 这些条目只是刷新被系统推迟时的兜底）
    static let hourlySpanCount = 12

    /// 没有城市数据时的重试间隔：等太久用户会以为「数据加载不出来」
    static let emptySnapshotRetryInterval: TimeInterval = 15 * 60

    static var entryCount: Int { minuteSpanCount + hourlySpanCount }

    struct Plan {
        /// 条目时间点，升序，首个条目为请求时刻 `now`
        let dates: [Date]
        /// 逐分钟精度失效、需要重新请求时间线的期限
        let reloadDate: Date
    }

    static func plan(from now: Date, calendar: Calendar = .current) -> Plan {
        var dates: [Date] = [now]
        dates.reserveCapacity(entryCount)

        // 逐个整分钟补齐：`now` 覆盖「刚添加 / 刚刷新」的渲染，其余条目按分钟边界推进，
        // 让时钟在整分钟处更新（WidgetKit 渲染时间点不晚于当前时刻的条目）。
        let nextMinute = calendar.nextDate(
            after: now,
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60)

        for offset in 0..<(minuteSpanCount - 1) {
            dates.append(nextMinute.addingTimeInterval(TimeInterval(offset * 60)))
        }

        // 最后一个逐分钟条目之后按小时步进，整体覆盖约 13 小时（刷新被推迟时的兜底）
        let minuteEnd = dates.last ?? now
        for offset in 1...hourlySpanCount {
            dates.append(minuteEnd.addingTimeInterval(TimeInterval(offset * 60 * 60)))
        }

        return Plan(dates: dates, reloadDate: minuteEnd)
    }

    /// 时间线的刷新期限。
    ///
    /// 有城市数据时，等到逐分钟精度失效（约 1 小时后）再请求新时间线；
    /// 没有任何城市时（App 还没发布过快照 / App Group 暂时读不到）用短间隔重试，
    /// 让组件尽早自愈，而不是把空态一直显示到 1 小时后。
    static func reloadDate(after now: Date, hasCities: Bool, plan: Plan) -> Date {
        guard !hasCities else { return plan.reloadDate }
        return min(plan.reloadDate, now.addingTimeInterval(emptySnapshotRetryInterval))
    }
}
