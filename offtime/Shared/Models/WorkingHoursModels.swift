import Foundation

/// 工作时段重叠计算结果：以本地 24 小时为轴。
struct WorkingHoursOverlap: Equatable {
    /// 48 个本地半小时槽（0–47），标记每个槽位是否双方均在工作时段。
    let halfHourlyOverlap: [Bool]
    /// 兼容旧界面/测试：任一半小时槽可联系即视为该小时有重叠。
    var hourlyOverlap: [Bool] {
        (0..<24).map { hour in
            halfHourlyOverlap[hour * 2] || halfHourlyOverlap[hour * 2 + 1]
        }
    }
    /// 当前时刻是否处于重叠时段。
    let isCurrentlyOverlapping: Bool
    /// 下一个重叠起点的绝对时间（可能落在今日或未来数日），nil 表示未来数日内无重叠。
    let nextOverlapDate: Date?
    /// 当前本地时刻在 24 小时轴上的位置（含分钟小数），用于色条"现在"标记。
    let currentLocalHour: Double
}
