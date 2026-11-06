import SwiftUI
import Combine
import SwiftData

// MARK: - CityDetailViewModel

/// 一个可联系槽位：本地触发时刻与目标城市对应时刻都使用分钟制。
struct ContactableSlot: Identifiable, Equatable {
    let localMinuteOfDay: Int
    let targetMinuteOfDay: Int
    let date: Date

    var id: Int { localMinuteOfDay }
}

@MainActor
final class CityDetailViewModel: ObservableObject {
    @Published var currentDate: Date = Date()
    @Published var localWorkStartMinutes: Int = MinuteTime.defaultWorkStartMinutes
    @Published var localWorkEndMinutes: Int = MinuteTime.defaultWorkEndMinutes
    @Published var targetWorkStartMinutes: Int
    @Published var targetWorkEndMinutes: Int
    @Published var use24Hour: Bool = true
    @Published var localTimezoneId: String = TimeZone.current.identifier
    /// 设置页当前城市名覆盖（优先于时区反推）
    @Published var localCityNameOverride: String?
    /// 设置页当前城市英文名覆盖（优先于时区反推）
    @Published var localCityEnOverride: String?
    @Published var reminders: [CityReminderGroup] = []
    @Published var reminderStatus: String?
    @Published private(set) var reminderStatusIsError = false

    let city: CityModel
    private let timezoneService = TimezoneService.shared
    private let reminderService: CityReminderService

    init(
        city: CityModel,
        reminderService: CityReminderService? = nil
    ) {
        self.city = city
        self.reminderService = reminderService ?? CityReminderService(
            modelContainer: CityService.shared.modelContainer
        )
        let targetWorkHours = city.workHours.sanitized()
        let localWorkHours = city.localWorkHours.sanitized()
        self.targetWorkStartMinutes = targetWorkHours.startMinutes
        self.targetWorkEndMinutes = targetWorkHours.endMinutes
        self.localWorkStartMinutes = localWorkHours.startMinutes
        self.localWorkEndMinutes = localWorkHours.endMinutes
    }

    // MARK: - Time Display

    var cityTime: String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: city.timezoneId, date: currentDate) ?? "--:--"
        }
        return timezoneService.getLocalTime12(timezoneId: city.timezoneId, date: currentDate) ?? "--:--"
    }

    var localTime: String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: localTimezoneId, date: currentDate) ?? "--:--"
        }
        return timezoneService.getLocalTime12(timezoneId: localTimezoneId, date: currentDate) ?? "--:--"
    }

    var timeDifference: String {
        timezoneService.getTimeDifferenceBetween(sourceTimezoneId: localTimezoneId, targetTimezoneId: city.timezoneId, date: currentDate).offset
    }

    /// 目标城市当前时间相对本地的跨天标签（昨日/明日）
    var targetCrossDay: String? {
        timezoneService.getTimeDifferenceBetween(sourceTimezoneId: localTimezoneId, targetTimezoneId: city.timezoneId, date: currentDate).crossDay
    }

    var isLocalCityDaytime: Bool {
        timezoneService.isDaytime(timezoneId: localTimezoneId, date: currentDate)
    }

    var isTargetCityDaytime: Bool {
        timezoneService.isDaytime(timezoneId: city.timezoneId, date: currentDate)
    }

    // MARK: - Timeline Data

    /// 本地当前时刻在 24 小时轴上的位置（含分钟小数）
    var localNowHour: Double {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: localTimezoneId) ?? .current
        let h = cal.component(.hour, from: currentDate)
        let m = cal.component(.minute, from: currentDate)
        return Double(h) + Double(m) / 60.0
    }

    /// 目标城市当前时刻在其自身 24 小时轴上的位置（含分钟小数）
    var targetNowHour: Double {
        guard let tz = TimeZone(identifier: city.timezoneId) else { return localNowHour }
        var cal = Calendar.current
        cal.timeZone = tz
        let h = cal.component(.hour, from: currentDate)
        let m = cal.component(.minute, from: currentDate)
        return Double(h) + Double(m) / 60.0
    }

    private var localWorkHours: WorkHours {
        WorkHours(startMinutes: localWorkStartMinutes, endMinutes: localWorkEndMinutes).sanitized()
    }

    private var targetWorkHours: WorkHours {
        WorkHours(startMinutes: targetWorkStartMinutes, endMinutes: targetWorkEndMinutes).sanitized()
    }

    /// 本地工作时段（48 个半小时槽，以本地 24 小时为轴）
    var localHalfHourlyWorking: [Bool] {
        (0..<48).map { localWorkHours.contains($0 * MinuteTime.stepMinutes) }
    }

    /// 目标城市工作时段（48 个半小时槽，以目标城市自身 24 小时为轴）
    var targetHalfHourlyWorking: [Bool] {
        (0..<48).map { targetWorkHours.contains($0 * MinuteTime.stepMinutes) }
    }

    /// 兼容旧界面：任一半小时槽为工作时间即视为该小时工作。
    var localHourlyWorking: [Bool] {
        (0..<24).map { localHalfHourlyWorking[$0 * 2] || localHalfHourlyWorking[$0 * 2 + 1] }
    }

    /// 兼容旧界面：任一半小时槽为工作时间即视为该小时工作。
    var targetHourlyWorking: [Bool] {
        (0..<24).map { targetHalfHourlyWorking[$0 * 2] || targetHalfHourlyWorking[$0 * 2 + 1] }
    }

    /// 可联系重叠时段（以本地 24 小时为轴，双方均在各自工作时段内）
    var overlap: WorkingHoursOverlap {
        timezoneService.getWorkingHoursOverlap(
            timezoneId: city.timezoneId,
            date: currentDate,
            localTimezoneId: localTimezoneId,
            localWorkStartMinutes: localWorkHours.startMinutes,
            localWorkEndMinutes: localWorkHours.endMinutes,
            targetWorkStartMinutes: targetWorkHours.startMinutes,
            targetWorkEndMinutes: targetWorkHours.endMinutes
        )
    }

    var overlapSummary: String {
        let halfHourly = overlap.halfHourlyOverlap
        var ranges: [(Int, Int)] = []
        var rangeStart: Int? = nil
        for slot in 0..<48 {
            if halfHourly[slot] {
                if rangeStart == nil { rangeStart = slot }
            } else if let start = rangeStart {
                ranges.append((start, slot))
                rangeStart = nil
            }
        }
        if let start = rangeStart { ranges.append((start, 48)) }
        guard !ranges.isEmpty else { return String(localized: "detail.contactable.none") }
        return ranges.map { range in
            let startMinutes = range.0 * MinuteTime.stepMinutes
            let endMinutes = range.1 * MinuteTime.stepMinutes
            let durationMinutes = endMinutes - startMinutes
            let hours = Double(durationMinutes) / Double(MinuteTime.minutesPerHour)
            let hoursText = hours.rounded() == hours
                ? String(format: "%.0f", hours)
                : String(format: "%.1f", hours)
            return String(
                format: String(localized: "detail.contactable.range"),
                MinuteTime.text(startMinutes),
                MinuteTime.text(endMinutes),
                hoursText,
                String(localized: "detail.hours")
            )
        }
        .joined(separator: "\n")
    }

    /// 与时钟列表一致的可联系状态提示
    var overlapStatusText: String {
        let overlap = overlap
        if overlap.isCurrentlyOverlapping {
            return String(localized: "clock.working.now")
        }
        if let nextOverlapDate = overlap.nextOverlapDate {
            return nextOverlapText(nextOverlapDate)
        }
        return String(localized: "clock.working.none")
    }

    private func nextOverlapText(_ date: Date) -> String {
        guard let localTimezone = TimeZone(identifier: localTimezoneId) else {
            return ""
        }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = localTimezone

        let formatter = DateFormatter()
        formatter.timeZone = localTimezone
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"

        let todayStart = localCalendar.dateInterval(of: .day, for: currentDate)?.start ?? currentDate
        let targetStart = localCalendar.dateInterval(of: .day, for: date)?.start ?? date
        let dayDifference = localCalendar.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0
        let timeText = formatter.string(from: date)

        if dayDifference > 0 {
            return "\(String(localized: "clock.tomorrow")) \(timeText)"
        }
        if dayDifference < 0 {
            return "\(String(localized: "clock.yesterday")) \(timeText)"
        }
        return timeText
    }

    /// 可联系槽位（按本地 30 分钟时间轴排列）。提醒时间使用本地槽位，
    /// 目标城市对应时刻由同一绝对时刻换算得到。
    var contactableSlots: [ContactableSlot] {
        guard let targetTZ = TimeZone(identifier: city.timezoneId),
              let localTZ = TimeZone(identifier: localTimezoneId) else {
            return []
        }

        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = targetTZ
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = localTZ
        guard let localDayStart = localCal.dateInterval(of: .day, for: currentDate)?.start else {
            return []
        }

        let resolvedLocalHours = localWorkHours
        let resolvedTargetHours = targetWorkHours
        var slots: [ContactableSlot] = []
        slots.reserveCapacity(48)

        for minuteOfDay in stride(from: 0, to: MinuteTime.minutesPerDay, by: MinuteTime.stepMinutes) {
            guard let date = localCal.date(
                byAdding: .minute,
                value: minuteOfDay,
                to: localDayStart
            ) else { continue }

            let localMinute = localCal.component(.hour, from: date) * MinuteTime.minutesPerHour
                + localCal.component(.minute, from: date)
            let targetMinute = targetCal.component(.hour, from: date) * MinuteTime.minutesPerHour
                + targetCal.component(.minute, from: date)
            guard resolvedLocalHours.contains(localMinute),
                  resolvedTargetHours.contains(targetMinute) else {
                continue
            }

            slots.append(
                ContactableSlot(
                    localMinuteOfDay: localMinute,
                    targetMinuteOfDay: targetMinute,
                    date: date
                )
            )
        }
        return slots
    }

    /// 可联系槽位的本地分钟列表，用于判断提醒是否已超出工作时段。
    var contactableLocalMinutes: [Int] {
        contactableSlots.map(\.localMinuteOfDay)
    }

    /// 兼容旧调用：按目标城市整点返回可联系小时（仅用于非 UI 的旧逻辑）。
    var contactableTargetHours: [Int] {
        contactableSlots
            .map { $0.targetMinuteOfDay / MinuteTime.minutesPerHour }
            .reduce(into: [Int]()) { result, hour in
                if result.last != hour { result.append(hour) }
            }
    }

    /// 目标城市时刻与同一绝对时刻在本地时区所属日期的跨天关系；同一天不标记
    func targetDayLabel(for date: Date) -> String? {
        guard let targetTZ = TimeZone(identifier: city.timezoneId),
              let localTZ = TimeZone(identifier: localTimezoneId) else {
            return nil
        }

        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = targetTZ
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = localTZ

        let dateComponents: Set<Calendar.Component> = [.year, .month, .day]
        let targetComponents = targetCal.dateComponents(dateComponents, from: date)
        let localComponents = localCal.dateComponents(dateComponents, from: date)

        guard let targetYear = targetComponents.year,
              let targetMonth = targetComponents.month,
              let targetDay = targetComponents.day,
              let localYear = localComponents.year,
              let localMonth = localComponents.month,
              let localDay = localComponents.day else {
            return nil
        }

        if targetYear < localYear
            || (targetYear == localYear && targetMonth < localMonth)
            || (targetYear == localYear && targetMonth == localMonth && targetDay < localDay) {
            return String(localized: "clock.yesterday")
        }

        if targetYear > localYear
            || (targetYear == localYear && targetMonth > localMonth)
            || (targetYear == localYear && targetMonth == localMonth && targetDay > localDay) {
            return String(localized: "clock.tomorrow")
        }

        return nil
    }

    func saveWorkHours() {
        let resolvedTargetHours = targetWorkHours
        let resolvedLocalHours = localWorkHours
        targetWorkStartMinutes = resolvedTargetHours.startMinutes
        targetWorkEndMinutes = resolvedTargetHours.endMinutes
        localWorkStartMinutes = resolvedLocalHours.startMinutes
        localWorkEndMinutes = resolvedLocalHours.endMinutes
        city.updateWorkHours(resolvedTargetHours)
        city.updateLocalWorkHours(resolvedLocalHours)
        try? CityService.shared.modelContainer?.mainContext.save()
        NotificationCenter.default.post(name: .cityStoreDidChange, object: nil)
    }

    // MARK: - City Reminder

    /// 已超出当前工作时段的提醒（本地触发分钟不在可联系槽位中）
    var orphanedReminders: [CityReminderGroup] {
        let contactableSet = Set(contactableLocalMinutes)
        return reminders.filter {
            !contactableSet.contains($0.hour * MinuteTime.minutesPerHour + $0.minute)
        }
    }

    func loadReminders() async {
        reminders = await reminderService.reminders(for: city.id)
    }

    /// 为可联系时段添加提醒：固定使用添加时的当前城市时间。
    @discardableResult
    func addContactableReminder(
        localMinuteOfDay: Int,
        targetMinuteOfDay: Int,
        weekdayPolicy: CityReminderWeekdayPolicy
    ) async -> Bool {
        reminderStatus = nil
        guard !hasReminder(atLocalMinute: localMinuteOfDay) else {
            reminderStatus = String(localized: "city.reminder.duplicate")
            reminderStatusIsError = true
            return false
        }

        guard MinuteTime.isValidClockTime(
            hour: MinuteTime.hour(of: localMinuteOfDay),
            minute: MinuteTime.minute(of: localMinuteOfDay)
        ) else {
            reminderStatus = CityReminderError.invalidTime.localizedDescription
            reminderStatusIsError = true
            return false
        }

        do {
            try await reminderService.addReminder(
                cityID: city.id,
                cityName: city.cityName,
                timezoneId: localTimezoneId,
                hour: MinuteTime.hour(of: localMinuteOfDay),
                minute: MinuteTime.minute(of: localMinuteOfDay),
                weekdayPolicy: weekdayPolicy,
                targetTimezoneId: city.timezoneId,
                targetHour: MinuteTime.hour(of: targetMinuteOfDay),
                targetMinute: MinuteTime.minute(of: targetMinuteOfDay),
                triggerCityName: localCityName,
                triggerCityEn: localCityEn
            )
            await loadReminders()
            reminderStatus = nil
            reminderStatusIsError = false
            return true
        } catch {
            reminderStatus = error.localizedDescription
            reminderStatusIsError = true
            return false
        }
    }

    /// 兼容旧调用：按整点添加提醒。
    @discardableResult
    func addContactableReminder(
        localHour: Int,
        targetHour: Int,
        weekdayPolicy: CityReminderWeekdayPolicy
    ) async -> Bool {
        await addContactableReminder(
            localMinuteOfDay: localHour * MinuteTime.minutesPerHour,
            targetMinuteOfDay: targetHour * MinuteTime.minutesPerHour,
            weekdayPolicy: weekdayPolicy
        )
    }

    /// 指定时刻（当前城市时区）是否已有提醒
    func hasReminder(atHour hour: Int, minute: Int) -> Bool {
        reminder(atHour: hour, minute: minute) != nil
    }

    /// 指定时刻（当前城市时区）已有的提醒
    func reminder(atHour hour: Int, minute: Int) -> CityReminderGroup? {
        reminders.first {
            $0.hour == hour && $0.minute == minute
        }
    }

    func hasReminder(atLocalMinute minuteOfDay: Int) -> Bool {
        reminder(atLocalMinute: minuteOfDay) != nil
    }

    func reminder(atLocalMinute minuteOfDay: Int) -> CityReminderGroup? {
        reminder(
            atHour: MinuteTime.hour(of: minuteOfDay),
            minute: MinuteTime.minute(of: minuteOfDay)
        )
    }

    /// 当前城市名（触发提醒的城市）——优先使用设置页选择的城市名
    var localCityName: String {
        localCityNameOverride ?? CityService.matchCity(for: localTimezoneId).name
    }

    /// 当前城市英文名——优先使用设置页选择的城市英文名
    var localCityEn: String {
        localCityEnOverride
            ?? CityService.matchCity(cityName: localCityName, timezoneId: localTimezoneId).en
    }

    /// 当前城市国家码
    var localCountryCode: String {
        CityService.countryCode(cityEn: localCityEn, timezoneId: localTimezoneId)
    }

    /// 目标城市国家码：优先取模型字段，旧数据为空时从内置城市目录按 英文名+时区 补全
    var targetCountryCode: String {
        if !city.country.isEmpty { return city.country }
        return CityService.countryCode(cityEn: city.cityEn, timezoneId: city.timezoneId)
    }

    /// 当前城市夏令时/冬令时状态
    var localDSTStatus: String? {
        timezoneService.getDSTStatus(timezoneId: localTimezoneId, date: currentDate)
    }

    /// 目标城市夏令时/冬令时状态
    var targetDSTStatus: String? {
        timezoneService.getDSTStatus(timezoneId: city.timezoneId, date: currentDate)
    }

    /// 目标城市某钟点对应的当前城市钟点（用于展示触发时间）
    func localHour(forTargetHour targetHour: Int) -> Int {
        guard let targetTZ = TimeZone(identifier: city.timezoneId),
              let localTZ = TimeZone(identifier: localTimezoneId) else {
            return targetHour
        }
        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = targetTZ
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = localTZ
        let dayStart = targetCal.startOfDay(for: currentDate)
        let date = targetCal.date(byAdding: .hour, value: targetHour, to: dayStart) ?? dayStart
        return localCal.component(.hour, from: date)
    }

    func removeReminder(_ reminder: CityReminderGroup) async {
        await reminderService.removeReminder(id: reminder.id)
        await loadReminders()
        reminderStatus = nil
        reminderStatusIsError = false
    }

}
