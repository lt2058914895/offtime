import Foundation

/// 分钟制时刻工具。
///
/// 可联系时段与提醒时间在内部统一使用“距离当天 00:00 的分钟数”表示，
/// 业务层只接受 30 分钟步进；展示层再格式化为 `HH:mm` 或 `24:00`。
enum MinuteTime {
    static let stepMinutes = 30
    static let minutesPerHour = 60
    static let minutesPerDay = 24 * minutesPerHour
    static let slotCount = minutesPerDay / stepMinutes
    static let defaultWorkStartMinutes = 9 * minutesPerHour
    static let defaultWorkEndMinutes = 18 * minutesPerHour

    static func hour(of minutes: Int) -> Int {
        minutes / minutesPerHour
    }

    static func minute(of minutes: Int) -> Int {
        minutes % minutesPerHour
    }

    static func isAlignedToStep(_ minutes: Int) -> Bool {
        minutes >= 0 && minutes.isMultiple(of: stepMinutes)
    }

    static func isTimeOfDayAlignedToStep(_ minutes: Int) -> Bool {
        (0..<minutesPerDay).contains(minutes) && isAlignedToStep(minutes)
    }

    static func isValidClockTime(hour: Int, minute: Int) -> Bool {
        (0..<24).contains(hour)
            && (0..<minutesPerHour).contains(minute)
            && minute.isMultiple(of: stepMinutes)
    }

    static func isValidWorkHours(startMinutes: Int, endMinutes: Int) -> Bool {
        isTimeOfDayAlignedToStep(startMinutes)
            && endMinutes >= stepMinutes
            && endMinutes <= minutesPerDay
            && isAlignedToStep(endMinutes)
            && startMinutes < endMinutes
    }

    /// 生成指定本地自然日内某个墙上时刻对应的绝对时间。
    /// 夏令时跳过的不存在时刻返回 nil；重复时刻取 Calendar 的默认首次出现。
    static func date(
        on localDay: Date,
        minuteOfDay: Int,
        calendar: Calendar
    ) -> Date? {
        guard isTimeOfDayAlignedToStep(minuteOfDay) else { return nil }
        let dayComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: localDay
        )
        guard let year = dayComponents.year,
              let month = dayComponents.month,
              let day = dayComponents.day else {
            return nil
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour(of: minuteOfDay)
        components.minute = minute(of: minuteOfDay)
        components.second = 0

        guard let date = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        guard actual.year == year,
              actual.month == month,
              actual.day == day,
              actual.hour == components.hour,
              actual.minute == components.minute else {
            return nil
        }
        return date
    }

    /// 按本地墙上时间增加分钟数。与 `Calendar.date(byAdding: .minute)` 不同，
    /// 该函数不会把跨夏令时的 30 分钟当作 30 分钟绝对时长，适合生成 24 小时时间轴槽位。
    static func date(
        byAddingWallClockMinutes minutes: Int,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else {
            return nil
        }

        let totalMinutes = hour * minutesPerHour + minute + minutes
        let dayOffset: Int
        let minuteOfDay: Int
        if totalMinutes >= 0 {
            dayOffset = totalMinutes / minutesPerDay
            minuteOfDay = totalMinutes % minutesPerDay
        } else {
            dayOffset = (totalMinutes - (minutesPerDay - 1)) / minutesPerDay
            minuteOfDay = totalMinutes - dayOffset * minutesPerDay
        }

        guard let shiftedDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: date
        ) else {
            return nil
        }
        return Self.date(on: shiftedDay, minuteOfDay: minuteOfDay, calendar: calendar)
    }

    /// 当前时刻到下一个 30 分钟本地槽位之间需要补齐的分钟数。
    static func minutesUntilNextSlot(from date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
        guard let minute = components.minute else { return 0 }
        let remainder = minute % stepMinutes
        if remainder != 0 {
            return stepMinutes - remainder
        }
        if (components.second ?? 0) != 0 || (components.nanosecond ?? 0) != 0 {
            return stepMinutes
        }
        return 0
    }

    /// 将任意输入收敛到合法的工作时段：起点向下取整到 30 分钟，终点向上取整到 30 分钟。
    static func sanitizedWorkHours(startMinutes: Int, endMinutes: Int) -> (start: Int, end: Int) {
        let clampedStart = min(max(startMinutes, 0), minutesPerDay - stepMinutes)
        let snappedStart = clampedStart - (clampedStart % stepMinutes)

        let clampedEnd = min(max(endMinutes, stepMinutes), minutesPerDay)
        let remainder = clampedEnd % stepMinutes
        let snappedEnd = remainder == 0 ? clampedEnd : clampedEnd + (stepMinutes - remainder)
        let boundedEnd = min(snappedEnd, minutesPerDay)

        guard snappedStart < boundedEnd else {
            return (snappedStart, min(minutesPerDay, snappedStart + stepMinutes))
        }
        return (snappedStart, boundedEnd)
    }

    static func text(_ minutes: Int) -> String {
        String(format: "%02d:%02d", hour(of: minutes), minute(of: minutes))
    }
}

/// 一段以分钟表示的工作时段。
struct WorkHours: Equatable, Hashable {
    var startMinutes: Int
    var endMinutes: Int

    static let `default` = WorkHours(
        startMinutes: MinuteTime.defaultWorkStartMinutes,
        endMinutes: MinuteTime.defaultWorkEndMinutes
    )

    var isValid: Bool {
        MinuteTime.isValidWorkHours(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    func contains(_ minuteOfDay: Int) -> Bool {
        minuteOfDay >= startMinutes && minuteOfDay < endMinutes
    }

    func sanitized() -> WorkHours {
        let hours = MinuteTime.sanitizedWorkHours(
            startMinutes: startMinutes,
            endMinutes: endMinutes
        )
        return WorkHours(startMinutes: hours.start, endMinutes: hours.end)
    }
}
