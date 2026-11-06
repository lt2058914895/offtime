import Foundation

/// 分钟制时刻工具。
///
/// 可联系时段与提醒时间在内部统一使用“距离当天 00:00 的分钟数”表示，
/// 业务层只接受 30 分钟步进；展示层再格式化为 `HH:mm` 或 `24:00`。
enum MinuteTime {
    static let stepMinutes = 30
    static let minutesPerHour = 60
    static let minutesPerDay = 24 * minutesPerHour
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
