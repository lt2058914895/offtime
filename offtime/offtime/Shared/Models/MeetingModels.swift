import Foundation

struct MeetingParticipant: Identifiable, Hashable {
    let id: String
    let cityName: String
    let cityEn: String
    let timezoneId: String
    let workStartHour: Int
    let workEndHour: Int
    let isLocal: Bool
}

struct MeetingOverlap: Equatable {
    let hourlyOverlap: [Bool]
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
