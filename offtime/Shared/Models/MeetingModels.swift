import Foundation

struct MeetingParticipant: Identifiable, Hashable {
    let id: String
    let cityName: String
    let cityEn: String
    let timezoneId: String
    let workStartMinutes: Int
    let workEndMinutes: Int
    let isLocal: Bool

    var workStartHour: Int { workStartMinutes / MinuteTime.minutesPerHour }
    var workEndHour: Int { workEndMinutes / MinuteTime.minutesPerHour }

    init(
        id: String,
        cityName: String,
        cityEn: String,
        timezoneId: String,
        workStartMinutes: Int,
        workEndMinutes: Int,
        isLocal: Bool
    ) {
        let hours = MinuteTime.sanitizedWorkHours(
            startMinutes: workStartMinutes,
            endMinutes: workEndMinutes
        )
        self.id = id
        self.cityName = cityName
        self.cityEn = cityEn
        self.timezoneId = timezoneId
        self.workStartMinutes = hours.start
        self.workEndMinutes = hours.end
        self.isLocal = isLocal
    }

    /// 兼容旧调用：整点参数在构造时换算为分钟。
    init(
        id: String,
        cityName: String,
        cityEn: String,
        timezoneId: String,
        workStartHour: Int,
        workEndHour: Int,
        isLocal: Bool
    ) {
        self.init(
            id: id,
            cityName: cityName,
            cityEn: cityEn,
            timezoneId: timezoneId,
            workStartMinutes: workStartHour * MinuteTime.minutesPerHour,
            workEndMinutes: workEndHour * MinuteTime.minutesPerHour,
            isLocal: isLocal
        )
    }
}

struct MeetingOverlap: Equatable {
    /// 48 个本地半小时槽。
    let halfHourlyOverlap: [Bool]
    /// 兼容旧调用：任一半小时槽重叠即视为该小时有重叠。
    var hourlyOverlap: [Bool] {
        (0..<24).map { hour in
            halfHourlyOverlap[hour * 2] || halfHourlyOverlap[hour * 2 + 1]
        }
    }
    let currentLocalHour: Double
    let isCurrentlyOverlapping: Bool
}

struct MeetingWindow: Identifiable, Hashable {
    /// 由起止小时派生，保证同一窗口多次计算时身份稳定
    var id: String { "\(startHour)-\(endHour)" }
    let startHour: Int
    let endHour: Int
    let durationHours: Int
    let startDate: Date
}

/// 参与者在某个时刻的可参会状态
enum MeetingParticipantState: Equatable {
    /// 工作时间
    case working
    /// 非工作且不在固定免打扰时段
    case awake
    /// 固定免打扰时段：每座城市本地 23:00–07:00
    case sleeping
}

/// 候选档期：给定时长与本地可选范围生成的推荐，附带打分统计
struct MeetingSlot: Identifiable, Hashable {
    var id: String { "\(Int(startDate.timeIntervalSince1970))-\(durationMinutes)" }
    let startDate: Date
    let segmentStart: Date
    let segmentEnd: Date
    let durationMinutes: Int
    let workingCount: Int
    let awakeCount: Int
    let sleepingCount: Int
    /// 0 = 全员工作；1 = 无人睡眠；2 = 有城市在睡眠
    let tier: Int
}

/// 一个连续状态时段内的候选开始时间。
/// endDate 表示状态时段结束时间，不一定表示会议结束时间。
struct MeetingSlotGroup: Identifiable, Hashable {
    var id: String {
        "\(Int(startDate.timeIntervalSince1970))-\(Int(endDate.timeIntervalSince1970))-\(tier)"
    }
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
    let tier: Int
    let workingCount: Int
    let awakeCount: Int
    let sleepingCount: Int
    /// 组内可选开始时刻（30 分钟步长）
    let optionStartDates: [Date]
}

/// 限制最长全员重叠的约束类型
enum MeetingConstraintKind: Equatable {
    /// 上班时间较晚，限制了重叠窗口的开始
    case start
    /// 下班时间较早，限制了重叠窗口的结束
    case end
}

/// 需要牺牲/调整工作时间的城市
struct MeetingConstraint: Identifiable, Hashable {
    let participant: MeetingParticipant
    let kind: MeetingConstraintKind

    var id: String { participant.id }
}
