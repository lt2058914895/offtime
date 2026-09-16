import XCTest
@testable import offtime

/// 小组件时间线规划回归测试。
///
/// 背景：大尺寸小组件添加后「数据没加载出来」，原因之一在时间线本身——
/// 旧实现用 `Calendar.date(bySetting: .second, value: 0, of: now)` 取整分钟，
/// 该 API 是向后寻找**下一个**整分钟，首个条目因此落在未来最多 60 秒处。
/// WidgetKit 只会渲染时间点不晚于当前时刻的条目，没有可渲染条目时组件停留在占位状态。
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

    private func startOfMinute(for date: Date, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        ))
    }

    func testFirstEntryNeverLandsInTheFuture() throws {
        let calendar = try calendar()

        for second in [1, 15, 30, 59] {
            let now = try instant(second: second)
            let dates = WidgetTimelineSchedule.plan(from: now, calendar: calendar).dates
            let first = try XCTUnwrap(dates.first)

            XCTAssertLessThanOrEqual(
                first,
                now,
                "首个条目不能在未来，否则刚添加/刷新的组件没有可渲染条目，看起来就是「数据没加载出来」"
            )
            let minuteStart = try startOfMinute(for: now, calendar: calendar)
            XCTAssertEqual(
                first.timeIntervalSince1970,
                minuteStart.timeIntervalSince1970,
                accuracy: 0.5,
                "首个条目应落在当前这一分钟"
            )
        }
    }

    func testEntriesAreSortedAndSwitchFromMinuteToHourly() throws {
        let calendar = try calendar()
        let dates = WidgetTimelineSchedule.plan(from: try instant(second: 30), calendar: calendar).dates

        XCTAssertEqual(dates.count, WidgetTimelineSchedule.entryCount)
        XCTAssertEqual(dates, dates.sorted())

        // 前 3 小时逐分钟：相邻条目相差 60 秒
        for index in 1..<WidgetTimelineSchedule.minuteSpanCount {
            XCTAssertEqual(dates[index].timeIntervalSince(dates[index - 1]), 60, accuracy: 0.5)
        }

        // 逐分钟段与逐小时段的衔接处仍相差 60 秒，之后才是整小时步进
        let hourlyStartIndex = WidgetTimelineSchedule.minuteSpanCount
        XCTAssertEqual(
            dates[hourlyStartIndex].timeIntervalSince(dates[hourlyStartIndex - 1]),
            60,
            accuracy: 0.5
        )
        for index in (hourlyStartIndex + 1)..<dates.count {
            XCTAssertEqual(dates[index].timeIntervalSince(dates[index - 1]), 3600, accuracy: 0.5)
        }
    }

    func testTimelineCoversRoughlyOneDay() throws {
        let calendar = try calendar()
        let now = try instant(second: 30)
        let dates = WidgetTimelineSchedule.plan(from: now, calendar: calendar).dates
        let last = try XCTUnwrap(dates.last)

        // 3 小时逐分钟 + 21 小时逐小时 ⇒ 最后一条约在 23 小时之后
        let expected = 23 * 60 * 60
        XCTAssertEqual(last.timeIntervalSince(now), Double(expected), accuracy: 61)
    }

    /// 逐分钟精度只覆盖前 3 小时，之后必须让系统重新请求时间线，
    /// 否则分钟显示会滞后，`.atEnd` 更是要等到约 23 小时后才刷新。
    func testReloadDateSitsAtTheEndOfTheMinuteSpan() throws {
        let calendar = try calendar()
        let now = try instant(second: 30)
        let plan = WidgetTimelineSchedule.plan(from: now, calendar: calendar)
        let minuteStart = try startOfMinute(for: now, calendar: calendar)

        XCTAssertEqual(
            plan.reloadDate.timeIntervalSince1970,
            minuteStart.addingTimeInterval(TimeInterval(WidgetTimelineSchedule.minuteSpanCount * 60)).timeIntervalSince1970,
            accuracy: 0.5,
            "重新请求时间线的期限应落在逐分钟条目的末尾（当前分钟 + 3 小时）"
        )
        XCTAssertLessThan(plan.reloadDate, try XCTUnwrap(plan.dates.last))
    }
}
