import SwiftUI
import Combine
import SwiftData

// MARK: - CityDetailViewModel

@MainActor
final class CityDetailViewModel: ObservableObject {
    @Published var currentDate: Date = Date()
    @Published var localWorkStart: Int = 9
    @Published var localWorkEnd: Int = 18
    @Published var targetWorkStart: Int
    @Published var targetWorkEnd: Int
    @Published var use24Hour: Bool = true
    @Published var localTimezoneId: String = TimeZone.current.identifier
    /// 设置页当前城市名覆盖（优先于时区反推）
    @Published var localCityNameOverride: String?
    /// 设置页当前城市英文名覆盖（优先于时区反推）
    @Published var localCityEnOverride: String?
    @Published var reminderWeekdaysOnly = true
    @Published var reminders: [CityReminderGroup] = []
    @Published var reminderStatus: String?
    @Published private(set) var reminderStatusIsError = false

    let city: CityModel
    private let timezoneService = TimezoneService.shared
    private let reminderService: CityReminderService

    init(
        city: CityModel,
        reminderService: CityReminderService = CityReminderService()
    ) {
        self.city = city
        self.reminderService = reminderService
        self.targetWorkStart = city.workStartHour
        self.targetWorkEnd = city.workEndHour
        self.localWorkStart = city.localWorkStart
        self.localWorkEnd = city.localWorkEnd
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

    /// 本地工作时段（以本地 24 小时为轴）
    var localHourlyWorking: [Bool] {
        (0..<24).map { $0 >= localWorkStart && $0 < localWorkEnd }
    }

    /// 目标城市工作时段（以目标城市自身 24 小时为轴）
    var targetHourlyWorking: [Bool] {
        (0..<24).map { $0 >= targetWorkStart && $0 < targetWorkEnd }
    }

    /// 可联系重叠时段（以本地 24 小时为轴，双方均在各自工作时段内）
    var overlap: WorkingHoursOverlap {
        timezoneService.getWorkingHoursOverlap(
            timezoneId: city.timezoneId,
            date: currentDate,
            localTimezoneId: localTimezoneId,
            localWorkStart: localWorkStart,
            localWorkEnd: localWorkEnd,
            targetWorkStart: targetWorkStart,
            targetWorkEnd: targetWorkEnd
        )
    }

    var overlapSummary: String {
        let hourly = overlap.hourlyOverlap
        var ranges: [(Int, Int)] = []
        var rangeStart: Int? = nil
        for hour in 0..<24 {
            if hourly[hour] {
                if rangeStart == nil { rangeStart = hour }
            } else if let start = rangeStart {
                ranges.append((start, hour))
                rangeStart = nil
            }
        }
        if let start = rangeStart { ranges.append((start, 24)) }
        guard !ranges.isEmpty else { return String(localized: "detail.contactable.none") }
        return ranges.map { range in
            let hours = range.1 - range.0
            return String(
                format: "%02d:00–%02d:00（%d%@）",
                range.0,
                range.1,
                hours,
                String(localized: "detail.hours")
            )
        }
        .joined(separator: "\n")
    }

    /// 可联系时间段（按目标城市时区 24 小时轴），提醒据此一键添加
    var contactableTargetRanges: [(startHour: Int, endHour: Int)] {
        guard let targetTZ = TimeZone(identifier: city.timezoneId),
              let localTZ = TimeZone(identifier: localTimezoneId) else {
            return []
        }

        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = targetTZ
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = localTZ
        let dayStart = targetCal.startOfDay(for: currentDate)

        var hourly: [Bool] = []
        for hour in 0..<24 {
            let date = targetCal.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart
            let localHour = localCal.component(.hour, from: date)
            hourly.append(
                hour >= targetWorkStart && hour < targetWorkEnd
                    && localHour >= localWorkStart && localHour < localWorkEnd
            )
        }

        var ranges: [(Int, Int)] = []
        var rangeStart: Int?
        for hour in 0..<24 {
            if hourly[hour] {
                if rangeStart == nil { rangeStart = hour }
            } else if let start = rangeStart {
                ranges.append((start, hour))
                rangeStart = nil
            }
        }
        if let start = rangeStart { ranges.append((start, 24)) }
        return ranges
    }

    /// 可联系时段（按本地触发时间升序排列的逐小时列表）
    var contactableTargetHours: [Int] {
        contactableTargetRanges
            .flatMap { ($0.startHour..<$0.endHour).map { $0 } }
            .sorted { localHour(forTargetHour: $0) < localHour(forTargetHour: $1) }
    }

    /// 目标城市时刻与同一绝对时刻在本地时区所属日期的跨天关系；同一天不标记
    func targetDayLabel(forTargetHour targetHour: Int) -> String? {
        guard let targetTZ = TimeZone(identifier: city.timezoneId),
              let localTZ = TimeZone(identifier: localTimezoneId) else {
            return nil
        }

        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = targetTZ
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = localTZ

        let targetDayStart = targetCal.startOfDay(for: currentDate)
        guard let targetDate = targetCal.date(byAdding: .hour, value: targetHour, to: targetDayStart) else {
            return nil
        }

        let dateComponents: Set<Calendar.Component> = [.year, .month, .day]
        let targetComponents = targetCal.dateComponents(dateComponents, from: targetDate)
        let localComponents = localCal.dateComponents(dateComponents, from: targetDate)

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
        city.workStartHour = targetWorkStart
        city.workEndHour = targetWorkEnd
        city.localWorkStart = localWorkStart
        city.localWorkEnd = localWorkEnd
        try? CityService.shared.modelContainer.mainContext.save()
    }

    // MARK: - City Reminder

    /// 已超出当前工作时段的提醒（targetHour 不在 contactableTargetHours 中）
    var orphanedReminders: [CityReminderGroup] {
        let contactableSet = Set(contactableTargetHours)
        return reminders.filter { !contactableSet.contains($0.targetHour) }
    }

    func loadReminders() async {
        reminders = await reminderService.reminders(for: city.id)
    }

    /// 为可联系时段添加提醒：按当前城市时间触发，通知中告知目标城市对应时刻
    func addContactableReminder(localHour: Int, targetHour: Int) async {
        reminderStatus = nil
        guard !hasReminder(atHour: localHour, minute: 0) else {
            reminderStatus = String(localized: "city.reminder.duplicate")
            reminderStatusIsError = true
            return
        }

        do {
            try await reminderService.addReminder(
                cityID: city.id,
                cityName: city.cityName,
                timezoneId: localTimezoneId,
                hour: localHour,
                minute: 0,
                weekdaysOnly: reminderWeekdaysOnly,
                targetTimezoneId: city.timezoneId,
                targetHour: targetHour,
                targetMinute: 0
            )
            await loadReminders()
            reminderStatus = nil
            reminderStatusIsError = false
        } catch {
            reminderStatus = error.localizedDescription
            reminderStatusIsError = true
        }
    }

    /// 指定时刻（当前城市时区）是否已有提醒
    func hasReminder(atHour hour: Int, minute: Int) -> Bool {
        reminder(atHour: hour, minute: minute) != nil
    }

    /// 指定时刻（当前城市时区）已有的提醒
    func reminder(atHour hour: Int, minute: Int) -> CityReminderGroup? {
        reminders.first {
            $0.hour == hour && $0.minute == minute && $0.weekdaysOnly == reminderWeekdaysOnly
        }
    }

    /// 当前城市名（触发提醒的城市）——优先使用设置页选择的城市名
    var localCityName: String {
        localCityNameOverride ?? CityService.matchCity(for: localTimezoneId).name
    }

    /// 当前城市英文名——优先使用设置页选择的城市英文名
    var localCityEn: String {
        localCityEnOverride ?? CityService.matchCity(for: localTimezoneId).en
    }

    /// 内置城市目录缓存：英文名+时区 → 国家码，用于补全旧数据缺失的 country 字段
    private static let countryCatalog: [String: String] = {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let cities = try? JSONDecoder().decode([CitySuggestion].self, from: data) else {
            return [:]
        }
        var catalog: [String: String] = [:]
        for city in cities {
            catalog["\(city.cityEn)|\(city.timezoneId)"] = city.country
        }
        return catalog
    }()

    /// 当前城市国家码
    var localCountryCode: String {
        Self.countryCatalog["\(localCityEn)|\(localTimezoneId)"] ?? ""
    }

    /// 目标城市国家码：优先取模型字段，旧数据为空时从内置城市目录按 英文名+时区 补全
    var targetCountryCode: String {
        if !city.country.isEmpty { return city.country }
        return Self.countryCatalog["\(city.cityEn)|\(city.timezoneId)"] ?? ""
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
