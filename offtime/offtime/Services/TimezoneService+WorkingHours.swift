import Foundation

// MARK: - Working Hours Overlap

/// 工作时段重叠计算结果：以本地 24 小时为轴。
struct WorkingHoursOverlap: Equatable {
    /// 24 个本地小时（0–23），标记每个小时是否为双方均在工作时段。
    let hourlyOverlap: [Bool]
    /// 当前时刻是否处于重叠时段。
    let isCurrentlyOverlapping: Bool
    /// 下一个重叠起始小时（本地时间，0–23），nil 表示今日无重叠。
    let nextOverlapHour: Int?
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
        localWorkStart: Int = 9,
        localWorkEnd: Int = 18,
        targetWorkStart: Int = 9,
        targetWorkEnd: Int = 18
    ) -> WorkingHoursOverlap {
        let empty = WorkingHoursOverlap(
            hourlyOverlap: Array(repeating: false, count: 24),
            isCurrentlyOverlapping: false,
            nextOverlapHour: nil
        )

        guard let targetTimezone = TimeZone(identifier: timezoneId) else {
            return empty
        }

        let localCalendar = Calendar.current
        var targetCalendar = Calendar.current
        targetCalendar.timeZone = targetTimezone

        guard let localStartOfDay = localCalendar.dateInterval(of: .day, for: date)?.start else {
            return empty
        }

        let currentLocalHour = localCalendar.component(.hour, from: date)
        var hourlyOverlap: [Bool] = []
        var isCurrentlyOverlapping = false
        var nextOverlapHour: Int? = nil

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

            if overlap && hour == currentLocalHour {
                isCurrentlyOverlapping = true
            }
            if overlap && nextOverlapHour == nil && hour >= currentLocalHour {
                nextOverlapHour = hour
            }
        }

        return WorkingHoursOverlap(
            hourlyOverlap: hourlyOverlap,
            isCurrentlyOverlapping: isCurrentlyOverlapping,
            nextOverlapHour: nextOverlapHour
        )
    }

}
