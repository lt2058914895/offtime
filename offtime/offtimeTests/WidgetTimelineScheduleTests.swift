import XCTest
@testable import offtime

/// 小组件时间线规划回归测试。
///
/// 背景：大尺寸小组件添加后「数据没加载出来」——时间线本身是原因之一。
///
/// 1. WidgetKit 只会渲染时间点不晚于当前时刻的条目，因此首个条目必须落在现在或过去；
///    旧实现用 `Calendar.date(bySetting: .second, value: 0, of: now)` 取整分钟，
///    该 API 会向后寻找**下一个**整分钟，首个条目因此落在未来最多 60 秒处。
///    现在首个条目直接取请求时刻 `now`。
/// 2. WidgetKit 会为时间线里的每一条 entry 渲染并归档一份视图，条目数越多、视图越复杂，
///    归档越大；大尺寸视图节点最多，超出系统预算后这份时间线就用不了，组件会一直停在
///    占位状态。所以逐分钟条目只保留 1 小时（此前是 3 小时），总条目数从 201 降到 72。
/// 3. 组件刚添加时若 App 还没发布过城市，时间线要短间隔重试，否则空态会一直挂着。
final class WidgetTimelineScheduleTests: XCTestCase {

    private func calendar(timezoneId: String = "Asia/Shanghai") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timezoneId))
        return calendar
    }

    /// 构造 10:15:xx 这种「分钟中间的某一秒」，用于暴露「首条目落在未来」的问题。
    private func instant(second: Int, timezoneId: String = "Asia/Shanghai") throws -> Date {
        let calendar = try calendar(timezoneId: timezoneId)
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 16,
            hour: 10,
            minute: 15,
            second: second
        )))
    }

    func testFirstEntryIsTheRequestTimeAndNeverLandsInTheFuture() throws {
        let calendar = try calendar()

        for second in [0, 1, 15, 30, 59] {
            let now = try instant(second: second)
            let dates = WidgetTimelineSchedule.plan(from: now, calendar: calendar).dates
            let first = try XCTUnwrap(dates.first)

            XCTAssertLessThanOrEqual(
                first,
                now,
                "首个条目不能在未来，否则刚添加/刷新的组件没有可渲染条目，看起来就是「数据没加载出来」"
            )
            XCTAssertEqual(
                first.timeIntervalSince1970,
                now.timeIntervalSince1970,
                accuracy: 0.5,
                "首个条目应就是请求时刻，不依赖任何取整"
            )
        }
    }

    func testEntriesAreSortedAndSwitchFromMinuteToHourly() throws {
        let calendar = try calendar()
        let dates = WidgetTimelineSchedule.plan(from: try instant(second: 30), calendar: calendar).dates

        XCTAssertEqual(dates.count, WidgetTimelineSchedule.entryCount)
        XCTAssertEqual(dates, dates.sorted())

        // 首条目是请求时刻，第二个条目落在下一个整分钟：间隔为 0~60 秒
        let firstGap = dates[1].timeIntervalSince(dates[0])
        XCTAssertGreaterThan(firstGap, 0)
        XCTAssertLessThanOrEqual(firstGap, 60)

        // 之后逐分钟：相邻条目相差 60 秒
        for index in 2..<WidgetTimelineSchedule.minuteSpanCount {
            XCTAssertEqual(dates[index].timeIntervalSince(dates[index - 1]), 60, accuracy: 0.5)
        }

        // 逐分钟段结束后按小时步进
        let hourlyStartIndex = WidgetTimelineSchedule.minuteSpanCount
        XCTAssertEqual(
            dates[hourlyStartIndex].timeIntervalSince(dates[hourlyStartIndex - 1]),
            3600,
            accuracy: 0.5
        )
        for index in (hourlyStartIndex + 1)..<dates.count {
            XCTAssertEqual(dates[index].timeIntervalSince(dates[index - 1]), 3600, accuracy: 0.5)
        }
    }

    func testTimelineStaysSmallAndCoversTheWholeDay() throws {
        let calendar = try calendar()
        let now = try instant(second: 30)
        let dates = WidgetTimelineSchedule.plan(from: now, calendar: calendar).dates
        let last = try XCTUnwrap(dates.last)

        // 逐分钟 1 小时（首条为 now）+ 逐小时 12 小时 ⇒ 最后一条约在 13 小时之后
        XCTAssertEqual(last.timeIntervalSince(now), 13 * 60 * 60, accuracy: 3 * 60)

        // 条目数直接决定 WidgetKit 的归档体积：必须保持在很小的量级
        XCTAssertLessThanOrEqual(
            WidgetTimelineSchedule.entryCount,
            72,
            "条目数不能放大：归档体积 ≈ 条目数 × 视图复杂度，大尺寸最容易因此停在占位状态"
        )
    }

    /// 逐分钟精度只覆盖前 1 小时，之后必须让系统重新请求时间线，
    /// 否则分钟显示会滞后，`.atEnd` 更是要等到约 13 小时后才刷新。
    func testReloadDateSitsAtTheEndOfTheMinuteSpan() throws {
        let calendar = try calendar()
        let now = try instant(second: 30)
        let plan = WidgetTimelineSchedule.plan(from: now, calendar: calendar)

        XCTAssertEqual(
            plan.reloadDate.timeIntervalSince1970,
            try XCTUnwrap(plan.dates[WidgetTimelineSchedule.minuteSpanCount - 1]).timeIntervalSince1970,
            accuracy: 0.5,
            "重新请求时间线的期限应落在最后一个逐分钟条目上"
        )
        XCTAssertLessThan(plan.reloadDate, try XCTUnwrap(plan.dates.last))
        XCTAssertLessThan(plan.reloadDate, now.addingTimeInterval(60 * 60 + 60))
    }

    /// 组件读不到城市（App 还没发布过快照 / App Group 暂时不可用）时必须短间隔重试，
    /// 否则空态会一直挂到下一次时间线刷新，用户看到的就是「数据迟迟加载不出来」。
    func testReloadDateRetriesSoonWhenThereAreNoCities() throws {
        let calendar = try calendar()
        let now = try instant(second: 30)
        let plan = WidgetTimelineSchedule.plan(from: now, calendar: calendar)

        let withCities = WidgetTimelineSchedule.reloadDate(after: now, hasCities: true, plan: plan)
        XCTAssertEqual(
            withCities.timeIntervalSince1970,
            plan.reloadDate.timeIntervalSince1970,
            accuracy: 0.5,
            "有城市时按分钟精度结束时间刷新即可"
        )

        let withoutCities = WidgetTimelineSchedule.reloadDate(after: now, hasCities: false, plan: plan)
        XCTAssertEqual(
            withoutCities.timeIntervalSince(now),
            WidgetTimelineSchedule.emptySnapshotRetryInterval,
            accuracy: 0.5,
            "没有城市时应缩短到重试间隔，尽早自愈"
        )
    }
}
