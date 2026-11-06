import Foundation

// MARK: - Working Hours Overlap

extension TimezoneService {
    /// 工作时段默认起止分钟（9:00–18:00）。
    static let workStartMinutes = MinuteTime.defaultWorkStartMinutes
    static let workEndMinutes = MinuteTime.defaultWorkEndMinutes

    /// 兼容旧调用：参数仍按整点传入，内部换算成分钟。
    func getWorkingHoursOverlap(
        timezoneId: String,
        date: Date = Date(),
        localTimezoneId: String = TimeZone.current.identifier,
        localWorkStart: Int = 9,
        localWorkEnd: Int = 18,
        targetWorkStart: Int = 9,
        targetWorkEnd: Int = 18
    ) -> WorkingHoursOverlap {
        getWorkingHoursOverlap(
            timezoneId: timezoneId,
            date: date,
            localTimezoneId: localTimezoneId,
            localWorkStartMinutes: localWorkStart * MinuteTime.minutesPerHour,
            localWorkEndMinutes: localWorkEnd * MinuteTime.minutesPerHour,
            targetWorkStartMinutes: targetWorkStart * MinuteTime.minutesPerHour,
            targetWorkEndMinutes: targetWorkEnd * MinuteTime.minutesPerHour
        )
    }

    /// 计算本地时区与目标时区的工作时段重叠情况（以本地 24 小时为轴）。
    /// 时段本身以分钟存储，按 30 分钟槽位输出；这样 9:30 开始/17:30 结束也能准确展示。
    func getWorkingHoursOverlap(
        timezoneId: String,
        date: Date = Date(),
        localTimezoneId: String = TimeZone.current.identifier,
        localWorkStartMinutes: Int = MinuteTime.defaultWorkStartMinutes,
        localWorkEndMinutes: Int = MinuteTime.defaultWorkEndMinutes,
        targetWorkStartMinutes: Int = MinuteTime.defaultWorkStartMinutes,
        targetWorkEndMinutes: Int = MinuteTime.defaultWorkEndMinutes
    ) -> WorkingHoursOverlap {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: localTimezoneId) ?? .current

        let currentHour = localCalendar.component(.hour, from: date)
        let currentMinute = localCalendar.component(.minute, from: date)
        let currentLocalHour = Double(currentHour) + Double(currentMinute) / 60.0

        let empty = WorkingHoursOverlap(
            halfHourlyOverlap: Array(repeating: false, count: 48),
            isCurrentlyOverlapping: false,
            nextOverlapDate: nil,
            currentLocalHour: currentLocalHour
        )

        guard let targetTimezone = TimeZone(identifier: timezoneId) else {
            return empty
        }

        var targetCalendar = Calendar(identifier: .gregorian)
        targetCalendar.timeZone = targetTimezone

        guard let localStartOfDay = localCalendar.dateInterval(of: .day, for: date)?.start else {
            return empty
        }

        let localWorkHours = WorkHours(
            startMinutes: localWorkStartMinutes,
            endMinutes: localWorkEndMinutes
        ).sanitized()
        let targetWorkHours = WorkHours(
            startMinutes: targetWorkStartMinutes,
            endMinutes: targetWorkEndMinutes
        ).sanitized()

        func minuteOfDay(for date: Date, calendar: Calendar) -> Int {
            calendar.component(.hour, from: date) * MinuteTime.minutesPerHour
                + calendar.component(.minute, from: date)
        }

        func isOverlapping(at date: Date) -> Bool {
            let localMinute = minuteOfDay(for: date, calendar: localCalendar)
            let targetMinute = minuteOfDay(for: date, calendar: targetCalendar)
            return localWorkHours.contains(localMinute) && targetWorkHours.contains(targetMinute)
        }

        var halfHourlyOverlap: [Bool] = []
        halfHourlyOverlap.reserveCapacity(48)
        for slot in 0..<48 {
            let slotDate = localCalendar.date(
                byAdding: .minute,
                value: slot * MinuteTime.stepMinutes,
                to: localStartOfDay
            ) ?? localStartOfDay
            halfHourlyOverlap.append(isOverlapping(at: slotDate))
        }

        let isCurrentlyOverlapping = isOverlapping(at: date)
        var nextOverlapDate: Date?

        // 当前不在重叠中时，找到下一个 30 分钟粒度的可联系起点。
        // 最多向后扫描 3 天，覆盖跨时区造成的跨日窗口。
        if !isCurrentlyOverlapping {
            outerLoop: for dayOffset in 0...2 {
                guard let dayStart = localCalendar.date(
                    byAdding: .day,
                    value: dayOffset,
                    to: localStartOfDay
                ) else { continue }

                for slot in 0..<48 {
                    guard let slotDate = localCalendar.date(
                        byAdding: .minute,
                        value: slot * MinuteTime.stepMinutes,
                        to: dayStart
                    ), slotDate > date else {
                        continue
                    }
                    if isOverlapping(at: slotDate) {
                        nextOverlapDate = slotDate
                        break outerLoop
                    }
                }
            }
        }

        return WorkingHoursOverlap(
            halfHourlyOverlap: halfHourlyOverlap,
            isCurrentlyOverlapping: isCurrentlyOverlapping,
            nextOverlapDate: nextOverlapDate,
            currentLocalHour: currentLocalHour
        )
    }
}
