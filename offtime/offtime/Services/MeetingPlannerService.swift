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

enum MeetingPlannerService {
    /// 单个参与者在其本地 24 小时轴上的工作时段（布尔数组，0–23 点）。
    static func workingHours(
        participant: MeetingParticipant,
        localTimezoneId: String,
        date: Date = Date()
    ) -> [Bool] {
        guard let timezone = TimeZone(identifier: participant.timezoneId),
              let localTimezone = TimeZone(identifier: localTimezoneId) else {
            return Array(repeating: false, count: 24)
        }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localTimezone
        guard let startOfDay = localCalendar.dateInterval(of: .day, for: date)?.start else {
            return Array(repeating: false, count: 24)
        }

        var participantCalendar = Calendar(identifier: .gregorian)
        participantCalendar.timeZone = timezone

        return (0..<24).map { hour in
            guard let hourDate = localCalendar.date(byAdding: .hour, value: hour, to: startOfDay) else {
                return false
            }
            let participantHour = participantCalendar.component(.hour, from: hourDate)
            return participantHour >= participant.workStartHour
                && participantHour < participant.workEndHour
        }
    }

    static func hourlyOverlap(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        date: Date = Date()
    ) -> MeetingOverlap {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = TimeZone(identifier: localTimezoneId) ?? .current

        let currentHour = localCalendar.component(.hour, from: date)
        let currentMinute = localCalendar.component(.minute, from: date)
        let currentHourDouble = Double(currentHour) + Double(currentMinute) / 60.0

        let empty = MeetingOverlap(
            hourlyOverlap: Array(repeating: false, count: 24),
            currentLocalHour: currentHourDouble,
            isCurrentlyOverlapping: false
        )

        guard !participants.isEmpty else {
            return empty
        }

        // 任一参与者时区非法时直接返回空结果，避免逐小时计算全部落空造成误判
        guard participants.allSatisfy({ TimeZone(identifier: $0.timezoneId) != nil }),
              let localTimezone = TimeZone(identifier: localTimezoneId) else {
            return empty
        }

        let perParticipantHours = participants.map {
            workingHours(participant: $0, localTimezoneId: localTimezone.identifier, date: date)
        }

        var hourlyOverlap: [Bool] = []
        var isCurrentlyOverlapping = false

        for hour in 0..<24 {
            let allWorking = perParticipantHours.allSatisfy { $0[hour] }
            hourlyOverlap.append(allWorking)
            if allWorking && hour == currentHour {
                isCurrentlyOverlapping = true
            }
        }

        return MeetingOverlap(
            hourlyOverlap: hourlyOverlap,
            currentLocalHour: currentHourDouble,
            isCurrentlyOverlapping: isCurrentlyOverlapping
        )
    }

    static func windows(
        hourlyOverlap: [Bool],
        localTimezoneId: String,
        date: Date = Date()
    ) -> [MeetingWindow] {
        guard let timezone = TimeZone(identifier: localTimezoneId) else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        var windows: [MeetingWindow] = []
        var start: Int?

        for hour in 0...24 {
            let isWorking = hour < 24 && hourlyOverlap.indices.contains(hour) && hourlyOverlap[hour]
            if isWorking {
                if start == nil {
                    start = hour
                }
            } else if let windowStart = start {
                windows.append(makeWindow(
                    startHour: windowStart,
                    endHour: hour,
                    calendar: calendar,
                    date: date
                ))
                start = nil
            }
        }

        return windows
            .sorted {
                if $0.durationHours != $1.durationHours {
                    return $0.durationHours > $1.durationHours
                }
                return $0.startHour < $1.startHour
            }
    }

    private static func makeWindow(
        startHour: Int,
        endHour: Int,
        calendar: Calendar,
        date: Date
    ) -> MeetingWindow {
        let startOfDay = calendar.dateInterval(of: .day, for: date)?.start ?? date
        let todayStart = calendar.date(byAdding: .hour, value: startHour, to: startOfDay) ?? date
        let startDate = todayStart > date ? todayStart : todayStart.addingTimeInterval(24 * 60 * 60)

        return MeetingWindow(
            startHour: startHour,
            endHour: endHour,
            durationHours: endHour - startHour,
            startDate: startDate
        )
    }
}

// MARK: - 推荐档期（打分排序）

/// 参与者在某个时刻的可参会状态
enum MeetingParticipantState: Equatable {
    /// 工作时间
    case working
    /// 醒着但不在工作时间（需牺牲）
    case awake
    /// 睡眠时间
    case sleeping
}

/// 候选档期：给定时长与本地可选范围生成的推荐，附带打分统计
struct MeetingSlot: Identifiable, Hashable {
    var id: String { "\(Int(startDate.timeIntervalSince1970))-\(durationMinutes)" }
    let startDate: Date
    let durationMinutes: Int
    let workingCount: Int
    let awakeCount: Int
    let sleepingCount: Int
    /// 0 = 全员工作；1 = 无人睡眠；2 = 有人睡眠
    let tier: Int
}

/// 由相邻 30 分钟档期合并而成的候选时间段：用户可在组内自行选择具体开始时间。
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

extension MeetingPlannerService {
    /// 默认睡眠窗口（与行程作息一致）：22:00 入睡、07:00 起床
    static let sleepStartHour = 22
    static let sleepEndHour = 7

    /// 参与者在指定绝对时刻的状态（按其自身时区判断）
    static func state(of participant: MeetingParticipant, at date: Date) -> MeetingParticipantState {
        guard let timezone = TimeZone(identifier: participant.timezoneId) else {
            return .awake
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        let workStart = participant.workStartHour * 60
        let workEnd = participant.workEndHour * 60
        if minutes >= workStart && minutes < workEnd {
            return .working
        }
        let sleepStart = sleepStartHour * 60
        let sleepEnd = sleepEndHour * 60
        if minutes >= sleepStart || minutes < sleepEnd {
            return .sleeping
        }
        return .awake
    }

    /// 参与者在 [startDate, endDate) 整段区间内的最差状态：
    /// 任一时间点处于睡眠 → 睡眠；任一时间点不在工作时间 → 非工作时间；全程在工作时间 → 工作中。
    static func state(
        of participant: MeetingParticipant,
        from startDate: Date,
        to endDate: Date
    ) -> MeetingParticipantState {
        guard endDate > startDate else {
            return state(of: participant, at: startDate)
        }
        guard let timezone = TimeZone(identifier: participant.timezoneId) else {
            return .awake
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let workStart = participant.workStartHour * 60
        let workEnd = participant.workEndHour * 60
        let sleepStart = sleepStartHour * 60
        let sleepEnd = sleepEndHour * 60

        var result: MeetingParticipantState = .working
        var cursor = startDate
        while cursor < endDate {
            let minutes = calendar.component(.hour, from: cursor) * 60
                + calendar.component(.minute, from: cursor)
            let current: MeetingParticipantState
            if minutes >= sleepStart || minutes < sleepEnd {
                current = .sleeping
            } else if minutes >= workStart && minutes < workEnd {
                current = .working
            } else {
                current = .awake
            }
            if current == .sleeping { return .sleeping }
            if current == .awake { result = .awake }
            cursor = cursor.addingTimeInterval(60)
        }
        return result
    }

    /// 在本地可选范围内按 30 分钟步长生成候选档期，并按
    /// 「全员工作 > 非睡眠 > 少数人牺牲」打分排序。
    /// 在指定日期范围内按 30 分钟步长生成候选档期，并按
    /// 「全员工作 > 非睡眠 > 少数人牺牲」打分排序。
    /// 已过时刻会被跳过，因此结果里的 startDate 恒为未来时间。
    static func recommendedSlots(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        durationMinutes: Int,
        startDate: Date,
        endDate: Date,
        date: Date = Date(),
        stepMinutes: Int = 30
    ) -> [MeetingSlot] {
        guard let localTimezone = TimeZone(identifier: localTimezoneId),
              !participants.isEmpty,
              durationMinutes > 0,
              endDate >= startDate else {
            return []
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localTimezone
        guard let rangeStart = calendar.dateInterval(of: .day, for: startDate)?.start,
              let rangeEnd = calendar.dateInterval(of: .day, for: endDate)?.start else {
            return []
        }

        var slots: [MeetingSlot] = []

        var day = rangeStart
        while day <= rangeEnd {
            let maxOffset = 24 * 60 - durationMinutes
            var offset = 0
            while offset <= maxOffset {
                guard let slotStart = calendar.date(byAdding: .minute, value: offset, to: day),
                      slotStart > date else {
                    offset += stepMinutes
                    continue
                }

                var working = 0
                var sleeping = 0
                var awake = 0
                for participant in participants {
                    let slotEnd = slotStart.addingTimeInterval(Double(durationMinutes) * 60)
                    switch state(of: participant, from: slotStart, to: slotEnd) {
                    case .working: working += 1
                    case .sleeping: sleeping += 1
                    case .awake: awake += 1
                    }
                }
                // 全员都在睡眠的档期没有参考价值，跳过
                if sleeping == participants.count {
                    offset += stepMinutes
                    continue
                }

                let tier: Int = working == participants.count ? 0 : (sleeping == 0 ? 1 : 2)
                slots.append(MeetingSlot(
                    startDate: slotStart,
                    durationMinutes: durationMinutes,
                    workingCount: working,
                    awakeCount: awake,
                    sleepingCount: sleeping,
                    tier: tier
                ))
                offset += stepMinutes
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        return slots.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.sleepingCount != $1.sleepingCount { return $0.sleepingCount < $1.sleepingCount }
            if $0.awakeCount != $1.awakeCount { return $0.awakeCount < $1.awakeCount }
            return $0.startDate < $1.startDate
        }
    }

    /// 将 30 分钟粒度的候选档期合并为时间段：时间相邻、状态（tier 与计数）一致的档期合并为一组。
    static func slotGroups(from slots: [MeetingSlot]) -> [MeetingSlotGroup] {
        let sorted = slots.sorted { $0.startDate < $1.startDate }
        var groups: [MeetingSlotGroup] = []
        var current: [MeetingSlot] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let endDate = last.startDate.addingTimeInterval(Double(last.durationMinutes) * 60)
            groups.append(
                MeetingSlotGroup(
                    startDate: first.startDate,
                    endDate: endDate,
                    durationMinutes: first.durationMinutes,
                    tier: first.tier,
                    workingCount: first.workingCount,
                    awakeCount: first.awakeCount,
                    sleepingCount: first.sleepingCount,
                    optionStartDates: current.map(\.startDate)
                )
            )
            current = []
        }

        for slot in sorted {
            let isAdjacent = current.last.map {
                slot.startDate == $0.startDate.addingTimeInterval(30 * 60)
            } ?? false
            let sameProfile = current.last.map {
                $0.tier == slot.tier
                    && $0.workingCount == slot.workingCount
                    && $0.awakeCount == slot.awakeCount
                    && $0.sleepingCount == slot.sleepingCount
                    && $0.durationMinutes == slot.durationMinutes
            } ?? false
            if isAdjacent && sameProfile {
                current.append(slot)
            } else {
                flush()
                current = [slot]
            }
        }
        flush()

        return groups.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.sleepingCount != $1.sleepingCount { return $0.sleepingCount < $1.sleepingCount }
            if $0.awakeCount != $1.awakeCount { return $0.awakeCount < $1.awakeCount }
            return $0.startDate < $1.startDate
        }
    }

    // MARK: - 重叠不足提示

    /// 日期范围内「全员都在工作」的最长连续分钟数（仅统计未来时间，30 分钟粒度）。
    static func maxOverlapMinutes(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        startDate: Date,
        endDate: Date,
        date: Date = Date()
    ) -> Int {
        longestAllWorkingSpan(
            participants: participants,
            localTimezoneId: localTimezoneId,
            startDate: startDate,
            endDate: endDate,
            date: date
        )?.minutes ?? 0
    }

    /// 哪些城市的工作时间边界限制了最长全员重叠（即需要牺牲/调整的城市）。
    static func constraintParticipants(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        startDate: Date,
        endDate: Date,
        date: Date = Date()
    ) -> [MeetingConstraint] {
        guard let span = longestAllWorkingSpan(
            participants: participants,
            localTimezoneId: localTimezoneId,
            startDate: startDate,
            endDate: endDate,
            date: date
        ) else { return [] }

        return participants.compactMap { participant in
            let beforeStart = state(of: participant, at: span.start.addingTimeInterval(-60))
            let atEnd = state(of: participant, at: span.end)
            if beforeStart != .working && atEnd != .working {
                return MeetingConstraint(participant: participant, kind: .start)
            }
            if beforeStart != .working {
                return MeetingConstraint(participant: participant, kind: .start)
            }
            if atEnd != .working {
                return MeetingConstraint(participant: participant, kind: .end)
            }
            return nil
        }
    }

    private static func longestAllWorkingSpan(
        participants: [MeetingParticipant],
        localTimezoneId: String,
        startDate: Date,
        endDate: Date,
        date: Date
    ) -> (start: Date, end: Date, minutes: Int)? {
        guard !participants.isEmpty,
              let localTimezone = TimeZone(identifier: localTimezoneId) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localTimezone
        guard let rangeStart = calendar.dateInterval(of: .day, for: startDate)?.start,
              let rangeEnd = calendar.dateInterval(of: .day, for: endDate)?.start,
              rangeEnd >= rangeStart else {
            return nil
        }

        var bestStart: Date?
        var bestMinutes = 0
        var currentStart: Date?
        var currentMinutes = 0

        var day = rangeStart
        while day <= rangeEnd {
            for offset in stride(from: 0, to: 24 * 60, by: 30) {
                guard let moment = calendar.date(byAdding: .minute, value: offset, to: day) else { continue }
                let allWorking = moment > date && participants.allSatisfy {
                    state(of: $0, at: moment) == .working
                }
                if allWorking {
                    if currentStart == nil { currentStart = moment }
                    currentMinutes += 30
                } else {
                    if currentMinutes > bestMinutes {
                        bestMinutes = currentMinutes
                        bestStart = currentStart
                    }
                    currentStart = nil
                    currentMinutes = 0
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        if currentMinutes > bestMinutes {
            bestMinutes = currentMinutes
            bestStart = currentStart
        }

        guard let start = bestStart, bestMinutes > 0 else { return nil }
        let end = calendar.date(byAdding: .minute, value: bestMinutes, to: start) ?? start
        return (start, end, bestMinutes)
    }
}
