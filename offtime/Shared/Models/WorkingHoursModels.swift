import Foundation

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
