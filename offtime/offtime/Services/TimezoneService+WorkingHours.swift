import Foundation

// MARK: - Working Hours Overlap

/// 工作时段重叠计算结果：以本地 24 小时为轴。
struct WorkingHoursOverlap: Equatable {
    /// 24 个本地小时（0–23），标记每个小时是否为双方均在工作时段。
    let hourlyOverlap: [Bool]
    /// 当前时刻是否处于重叠时段。
    let isCurrentlyOverlapping: Bool
    /// 下一个重叠起点的绝对时间（可能落在今日或明日），nil 表示未来 48 小时内无重叠。
    let nextOverlapDate: Date?
    /// 当前本地时刻在 24 小时轴上的位置（含分钟小数），用于色条"现在"标记。
    let currentLocalHour: Double
}

extension TimezoneService {
    /// 工作时段默认起止小时（9:00–18:00）。
    static let workStartHour = 9
    static let workEndHour = 18

    /// 计算本地时区与目标时区的工作时段重叠情况（以本地 24 小时为轴）。
    /// 逐小时判断：该本地小时是否同时落在本地与目标城市的工作时段内。
    func getWorkingHoursOverlap(
        timezoneId: String,
        date: Date = Date(),
        localTimezoneId: String = TimeZone.current.identifier,
        localWorkStart: Int = 9,
        localWorkEnd: Int = 18,
        targetWorkStart: Int = 9,
        targetWorkEnd: Int = 18
    ) -> WorkingHoursOverlap {
        var localCalendar = Calendar.current
        localCalendar.timeZone = TimeZone(identifier: localTimezoneId) ?? .current
        let currentLocalHourInt = localCalendar.component(.hour, from: date)
        let currentLocalMinute = localCalendar.component(.minute, from: date)
        let currentLocalHourDouble = Double(currentLocalHourInt) + Double(currentLocalMinute) / 60.0

        let empty = WorkingHoursOverlap(
            hourlyOverlap: Array(repeating: false, count: 24),
            isCurrentlyOverlapping: false,
            nextOverlapDate: nil,
            currentLocalHour: currentLocalHourDouble
        )

        guard let targetTimezone = TimeZone(identifier: timezoneId) else {
            return empty
        }

        var targetCalendar = Calendar.current
        targetCalendar.timeZone = targetTimezone

        guard let localStartOfDay = localCalendar.dateInterval(of: .day, for: date)?.start else {
            return empty
        }

        var hourlyOverlap: [Bool] = []
        var isCurrentlyOverlapping = false
        var nextOverlapDate: Date? = nil

        for hour in 0..<24 {
            guard let hourDate = localCalendar.date(byAdding: .hour, value: hour, to: localStartOfDay) else {
                hourlyOverlap.append(false)
                continue
            }

            let localWorking = hour >= localWorkStart && hour < localWorkEnd
            let targetHour = targetCalendar.component(.hour, from: hourDate)
            let targetWorking = targetHour >= targetWorkStart && targetHour < targetWorkEnd
            let overlap = localWorking && targetWorking
            hourlyOverlap.append(overlap)

            if overlap && hour == currentLocalHourInt {
                isCurrentlyOverlapping = true
            }
            // 当日未来重叠起点：尚未设置且该小时在当前时刻及之后
            if overlap && nextOverlapDate == nil && hour >= currentLocalHourInt {
                nextOverlapDate = hourDate
            }
        }

        // 当日已无未来重叠时，向前扫描次日，覆盖跨天重叠窗口（最多 48h）。
        // 仅当当前不在重叠且当日没有未到的重叠时才需要，避免覆盖「今日还有」的提示。
        if nextOverlapDate == nil && !isCurrentlyOverlapping {
            for step in 1...48 {
                guard let futureDate = localCalendar.date(byAdding: .hour, value: step, to: date) else { break }
                let futureLocalHour = localCalendar.component(.hour, from: futureDate)
                let futureTargetHour = targetCalendar.component(.hour, from: futureDate)
                let localWorking = futureLocalHour >= localWorkStart && futureLocalHour < localWorkEnd
                let targetWorking = futureTargetHour >= targetWorkStart && futureTargetHour < targetWorkEnd
                if localWorking && targetWorking {
                    // 对齐到该小时起点作为重叠起点
                    nextOverlapDate = localCalendar.dateInterval(of: .hour, for: futureDate)?.start ?? futureDate
                    break
                }
            }
        }

        return WorkingHoursOverlap(
            hourlyOverlap: hourlyOverlap,
            isCurrentlyOverlapping: isCurrentlyOverlapping,
            nextOverlapDate: nextOverlapDate,
            currentLocalHour: currentLocalHourDouble
        )
    }

}
