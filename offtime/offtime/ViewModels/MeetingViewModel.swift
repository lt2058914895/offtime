import Foundation
import Combine
import SwiftUI

@MainActor
final class MeetingViewModel: ObservableObject {
    @Published var participants: [MeetingParticipant] = []
    @Published var selectedIDs: Set<String> = []
    @Published var localTimezoneId: String = TimeZone.current.identifier
    @Published var currentDate: Date = Date()
    /// 会议时长（分钟）
    @Published var durationMinutes: Int = 60
    /// 会议日期（本地自然日）
    @Published var meetingDate: Date

    private let cityService: CityService
    private let timezoneService: TimezoneService

    private static let lastSelectedIDsKey = "meeting_lastSelectedParticipantIDs"

    init(cityService: CityService? = nil) {
        self.cityService = cityService ?? .shared
        self.timezoneService = .shared

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        self.meetingDate = today
    }

    var selectedParticipants: [MeetingParticipant] {
        participants.filter { selectedIDs.contains($0.id) }
    }

    var overlap: MeetingOverlap {
        MeetingPlannerService.hourlyOverlap(
            participants: selectedParticipants,
            localTimezoneId: localTimezoneId,
            date: currentDate
        )
    }

    var windows: [MeetingWindow] {
        MeetingPlannerService.windows(
            hourlyOverlap: overlap.hourlyOverlap,
            localTimezoneId: localTimezoneId,
            date: currentDate
        )
    }

    /// 距离现在最近的（下一个）重叠窗口：窗口 startDate 恒为未来时间，取最早即最近
    var nextWindow: MeetingWindow? {
        windows.min { $0.startDate < $1.startDate }
    }

    /// 推荐档期（已按「全员工作 > 非睡眠 > 少数人牺牲」排序）
    var slots: [MeetingSlot] {
        MeetingPlannerService.recommendedSlots(
            participants: selectedParticipants,
            localTimezoneId: localTimezoneId,
            durationMinutes: durationMinutes,
            startDate: meetingDate,
            endDate: meetingDate,
            date: currentDate
        )
    }

    /// 合并后的推荐档期时间段（供列表展示，进入详情后再选具体开始时间）
    var slotGroups: [MeetingSlotGroup] {
        MeetingPlannerService.slotGroups(from: slots)
    }

    /// 日期选择菜单可选的自然日（今天起 14 天，按本地时区）
    var dateOptions: [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: localTimezoneId) ?? .current
        let today = calendar.startOfDay(for: currentDate)
        return (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// 会议日期内全员重叠的最长分钟数（不足会议时长时用于提示）
    var maxOverlapMinutes: Int {
        MeetingPlannerService.maxOverlapMinutes(
            participants: selectedParticipants,
            localTimezoneId: localTimezoneId,
            startDate: meetingDate,
            endDate: meetingDate,
            date: currentDate
        )
    }

    /// 限制最长全员重叠、需要牺牲调整的城市
    var constraints: [MeetingConstraint] {
        MeetingPlannerService.constraintParticipants(
            participants: selectedParticipants,
            localTimezoneId: localTimezoneId,
            startDate: meetingDate,
            endDate: meetingDate,
            date: currentDate
        )
    }

    /// 选中城市的名称（用于保存会议记录）
    var participantNames: [String] {
        selectedParticipants.map(\.cityName)
    }

    func workingHours(for participant: MeetingParticipant) -> [Bool] {
        MeetingPlannerService.workingHours(
            participant: participant,
            localTimezoneId: localTimezoneId,
            date: currentDate
        )
    }

    /// 保存最近一次成功添加会议时的参与者选中状态，下次进入会议页时自动恢复。
    func saveSelectedParticipantIDs() {
        let ids = Array(selectedIDs)
        UserDefaults.standard.set(ids, forKey: Self.lastSelectedIDsKey)
    }

    /// 加载上次保存的参与者选中 ID（仅在添加过会议后才有值）。
    private func loadLastSelectedParticipantIDs() -> Set<String>? {
        guard let ids = UserDefaults.standard.stringArray(forKey: Self.lastSelectedIDsKey),
              !ids.isEmpty else {
            return nil
        }
        return Set(ids)
    }

    func loadParticipants(
        localTimezoneId: String,
        localCityName: String?,
        localCityEn: String?
    ) {
        self.localTimezoneId = localTimezoneId
        normalizeMeetingDateIfNeeded()

        let localName = localCityName
            ?? CityService.matchCity(for: localTimezoneId).name
        let localEn = localCityEn
            ?? CityService.matchCity(for: localTimezoneId).en

        var loaded: [MeetingParticipant] = [
            MeetingParticipant(
                id: "local",
                cityName: localName,
                cityEn: localEn,
                timezoneId: localTimezoneId,
                workStartHour: TimezoneService.workStartHour,
                workEndHour: TimezoneService.workEndHour,
                isLocal: true
            )
        ]

        let localKey = CityIdentity.key(cityEn: localEn, timezoneId: localTimezoneId)

        if let cities = try? cityService.getAllCities() {
            for city in cities {
                let cityKey = CityIdentity.key(cityEn: city.cityEn, timezoneId: city.timezoneId)
                if cityKey == localKey { continue }
                loaded.append(
                    MeetingParticipant(
                        id: city.id.uuidString,
                        cityName: city.cityName,
                        cityEn: city.cityEn,
                        timezoneId: city.timezoneId,
                        workStartHour: city.workStartHour,
                        workEndHour: city.workEndHour,
                        isLocal: false
                    )
                )
            }
        }

        // 保持已有勾选（按 id 稳定），并确保默认选中前 3 个
        let validIDs = Set(loaded.map(\.id))
        selectedIDs.formIntersection(validIDs)
        if selectedIDs.isEmpty {
            // 优先恢复上次添加会议时保存的选中状态
            if let savedIDs = loadLastSelectedParticipantIDs() {
                selectedIDs = savedIDs.intersection(validIDs)
            }
            // 如果没有保存记录或保存的 ID 已失效，则默认选中前 3 个
            if selectedIDs.isEmpty {
                let defaultCount = min(loaded.count, 3)
                selectedIDs = Set(loaded.prefix(defaultCount).map(\.id))
            }
        }

        participants = loaded
    }

    /// 会议日期默认从「今天」开始；跨天后自动把已过日期校正到今天。
    private func normalizeMeetingDateIfNeeded() {
        guard let today = dateOptions.first else { return }
        if meetingDate < today {
            meetingDate = today
        }
    }

    func toggleParticipant(_ participant: MeetingParticipant) {
        if selectedIDs.contains(participant.id) {
            selectedIDs.remove(participant.id)
        } else {
            selectedIDs.insert(participant.id)
        }
    }

    var localParticipant: MeetingParticipant? {
        participants.first { $0.isLocal }
    }

    var targetParticipant: MeetingParticipant? {
        selectedParticipants.first { !$0.isLocal && $0.timezoneId != localTimezoneId }
            ?? selectedParticipants.first { !$0.isLocal }
            ?? localParticipant
    }

    /// 指定开始时刻与时长时，各参与者时区下的起止时间与状态（用于详情弹层）。
    func slotDetail(startDate: Date, durationMinutes: Int, use24Hour: Bool) -> MeetingSlotDetail {
        let endDate = startDate.addingTimeInterval(Double(durationMinutes) * 60)
        let rows = selectedParticipants.map { participant in
            let startText = formatBoundary(date: startDate, participant: participant, use24Hour: use24Hour)
            let endText = formatBoundary(date: endDate, participant: participant, use24Hour: use24Hour)
            return MeetingSlotRow(
                id: participant.id,
                cityName: participant.cityName,
                cityEn: participant.cityEn,
                isLocal: participant.isLocal,
                timeText: "\(startText) – \(endText)",
                state: MeetingPlannerService.state(of: participant, from: startDate, to: endDate)
            )
        }
        let slot = MeetingSlot(
            startDate: startDate,
            durationMinutes: durationMinutes,
            workingCount: selectedParticipants.count,
            awakeCount: 0,
            sleepingCount: 0,
            tier: 0
        )
        return MeetingSlotDetail(slot: slot, rows: rows)
    }

    private func formatBoundary(
        date: Date,
        participant: MeetingParticipant,
        use24Hour: Bool
    ) -> String {
        let time = use24Hour
            ? timezoneService.getLocalTime24(timezoneId: participant.timezoneId, date: date) ?? ""
            : timezoneService.getLocalTime12(timezoneId: participant.timezoneId, date: date) ?? ""

        guard let localTimezone = TimeZone(identifier: localTimezoneId),
              let participantTimezone = TimeZone(identifier: participant.timezoneId) else {
            return time
        }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localTimezone
        var participantCalendar = Calendar(identifier: .gregorian)
        participantCalendar.timeZone = participantTimezone

        // 本地时区无需日期前缀：会议日期已在标题显示，时间范围自然连续
        if participant.isLocal {
            return time
        }

        // 参考日为会议日期（本地时区），而非边界时刻的本地日
        let referenceDay = dayOrder(localCalendar.dateComponents([.year, .month, .day], from: meetingDate))
        let participantDay = dayOrder(participantCalendar.dateComponents([.year, .month, .day], from: date))

        if participantDay != referenceDay {
            // 跨天时显示参与者时区下的具体日期，避免相对标签的歧义
            var style = Date.FormatStyle.dateTime.month(.defaultDigits).day()
            style.timeZone = participantTimezone
            let dateStr = date.formatted(style)
            return "\(dateStr) \(time)"
        }
        return time
    }

    /// 将日历日期转为可比较的年月日序号（同日返回相同值，跨时区比较不再受零点时刻影响）。
    private func dayOrder(_ components: DateComponents) -> Int {
        (components.year ?? 0) * 10000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }
}

struct MeetingSlotDetail: Identifiable {
    let slot: MeetingSlot
    let rows: [MeetingSlotRow]

    var id: String { slot.id }
}

struct MeetingSlotRow: Identifiable {
    let id: String
    let cityName: String
    let cityEn: String
    let isLocal: Bool
    let timeText: String
    let state: MeetingParticipantState
}
