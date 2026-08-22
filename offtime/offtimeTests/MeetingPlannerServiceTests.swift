import XCTest
@testable import offtime

final class MeetingPlannerServiceTests: XCTestCase {
    private let shanghai = MeetingParticipant(
        id: "sh",
        cityName: "Shanghai",
        cityEn: "Shanghai",
        timezoneId: "Asia/Shanghai",
        workStartHour: 9,
        workEndHour: 18,
        isLocal: true
    )

    private let london = MeetingParticipant(
        id: "ldn",
        cityName: "London",
        cityEn: "London",
        timezoneId: "Europe/London",
        workStartHour: 9,
        workEndHour: 18,
        isLocal: false
    )

    private let losAngeles = MeetingParticipant(
        id: "la",
        cityName: "Los Angeles",
        cityEn: "Los Angeles",
        timezoneId: "America/Los_Angeles",
        workStartHour: 9,
        workEndHour: 18,
        isLocal: false
    )

    private func date(hour: Int, minute: Int = 0, timezoneId: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneId)!
        return calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 21, hour: hour, minute: minute)
        )!
    }

    private func shanghaiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    // MARK: - 工作时段重叠

    func testTwoCityOverlapFindsCommonWorkingHours() {
        // 上海轴：上海 9–18，伦敦（UTC+1）9–18 = 上海 16:00–次日 01:00
        // 交集 = 16、17 两个整点小时
        let overlap = MeetingPlannerService.hourlyOverlap(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertEqual(overlap.hourlyOverlap.filter { $0 }.count, 2)
        XCTAssertTrue(overlap.hourlyOverlap[16])
        XCTAssertTrue(overlap.hourlyOverlap[17])
        XCTAssertFalse(overlap.hourlyOverlap[15])
        XCTAssertFalse(overlap.hourlyOverlap[18])
        XCTAssertEqual(overlap.currentLocalHour, 12, accuracy: 0.01)
        XCTAssertFalse(overlap.isCurrentlyOverlapping)
    }

    func testOverlapDuringCurrentHourFlagsCurrentlyOverlapping() {
        // 上海 16:30 正处于上海+伦敦交集内
        let overlap = MeetingPlannerService.hourlyOverlap(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 16, minute: 30, timezoneId: "Asia/Shanghai")
        )

        XCTAssertTrue(overlap.isCurrentlyOverlapping)
        XCTAssertEqual(overlap.currentLocalHour, 16.5, accuracy: 0.01)
    }

    func testThreeCityWithoutFullOverlapReturnsEmpty() {
        // 上海 9–18、洛杉矶 9–18 = 上海 00:00–09:00、伦敦 = 上海 16:00–次日 01:00
        // 三方在当日轴上无交集
        let overlap = MeetingPlannerService.hourlyOverlap(
            participants: [shanghai, losAngeles, london],
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertFalse(overlap.hourlyOverlap.contains(true))
        XCTAssertFalse(overlap.isCurrentlyOverlapping)
    }

    func testSingleParticipantWorkingHoursMatchItsOwnSchedule() {
        let hours = MeetingPlannerService.workingHours(
            participant: shanghai,
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours.filter { $0 }.count, 9)
        XCTAssertTrue(hours[9])
        XCTAssertTrue(hours[17])
        XCTAssertFalse(hours[8])
        XCTAssertFalse(hours[18])
    }

    func testWindowsSortedByDurationDescendingThenStartAscending() {
        var overlap = Array(repeating: false, count: 24)
        for hour in 0..<2 { overlap[hour] = true }
        for hour in 3..<6 { overlap[hour] = true }

        let windows = MeetingPlannerService.windows(
            hourlyOverlap: overlap,
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].startHour, 3)
        XCTAssertEqual(windows[0].endHour, 6)
        XCTAssertEqual(windows[0].durationHours, 3)
        XCTAssertEqual(windows[1].startHour, 0)
        XCTAssertEqual(windows[1].durationHours, 2)
    }

    func testWindowStartDateIsNextOccurrenceInLocalTime() {
        var overlap = Array(repeating: false, count: 24)
        for hour in 14..<16 { overlap[hour] = true }

        let windows = MeetingPlannerService.windows(
            hourlyOverlap: overlap,
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        let window = try! XCTUnwrap(windows.first)
        let hour = shanghaiCalendar().component(.hour, from: window.startDate)
        XCTAssertEqual(hour, 14)
    }

    func testEmptyParticipantsReturnEmptyOverlap() {
        let overlap = MeetingPlannerService.hourlyOverlap(
            participants: [],
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertEqual(overlap.hourlyOverlap, Array(repeating: false, count: 24))
        XCTAssertFalse(overlap.isCurrentlyOverlapping)
        XCTAssertTrue(MeetingPlannerService.windows(
            hourlyOverlap: overlap.hourlyOverlap,
            localTimezoneId: "Asia/Shanghai",
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        ).isEmpty)
    }

    // MARK: - 推荐档期

    func testRecommendedSlotsPutAllWorkingFirst() {
        // 上海+伦敦：16:00–18:00 全员工作，应优先推荐
        let slots = MeetingPlannerService.recommendedSlots(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            durationMinutes: 60,
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        let top = try! XCTUnwrap(slots.first)
        XCTAssertEqual(top.tier, 0)
        XCTAssertEqual(top.workingCount, 2)
        XCTAssertEqual(top.sleepingCount, 0)
        XCTAssertEqual(top.awakeCount, 0)
        XCTAssertEqual(shanghaiCalendar().component(.hour, from: top.startDate), 16)
    }

    func testRecommendedSlotsSortsByTier() {
        // 上海+洛杉矶：上海 9–18 内洛杉矶处于睡眠（上海轴 13:00–22:00），无全员工作档期；
        // 09:00–12:30 为 tier 1（无人睡眠），13:00 起为 tier 2（洛杉矶睡眠）
        let slots = MeetingPlannerService.recommendedSlots(
            participants: [shanghai, losAngeles],
            localTimezoneId: "Asia/Shanghai",
            durationMinutes: 60,
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertFalse(slots.isEmpty)
        XCTAssertEqual(slots.first?.tier, 1)
        XCTAssertEqual(slots.first?.sleepingCount, 0)
        XCTAssertEqual(slots.first?.awakeCount, 1)

        guard let firstSleepingIndex = slots.firstIndex(where: { $0.tier == 2 }) else {
            return XCTFail("expected tier 2 slots")
        }
        XCTAssertTrue(slots[..<firstSleepingIndex].allSatisfy { $0.tier == 1 })
        XCTAssertTrue(slots[firstSleepingIndex...].allSatisfy { $0.tier == 2 })
        XCTAssertEqual(slots[firstSleepingIndex].sleepingCount, 1)
        XCTAssertEqual(slots[firstSleepingIndex].workingCount, 1)
    }

    func testRecommendedSlotsPreferFewerSacrificesWithinTier() {
        // 同一时区、不同工作时段：p1/p2 9–18，p3 11–16，p4 14–18
        // 14:00 起全员工作（tier 0）；11:00–14:00 仅 p4 牺牲；09:00–11:00 有 2 人牺牲
        let p1 = MeetingParticipant(id: "1", cityName: "A", cityEn: "A", timezoneId: "Asia/Shanghai", workStartHour: 9, workEndHour: 18, isLocal: true)
        let p2 = MeetingParticipant(id: "2", cityName: "B", cityEn: "B", timezoneId: "Asia/Shanghai", workStartHour: 9, workEndHour: 18, isLocal: false)
        let p3 = MeetingParticipant(id: "3", cityName: "C", cityEn: "C", timezoneId: "Asia/Shanghai", workStartHour: 11, workEndHour: 16, isLocal: false)
        let p4 = MeetingParticipant(id: "4", cityName: "D", cityEn: "D", timezoneId: "Asia/Shanghai", workStartHour: 14, workEndHour: 18, isLocal: false)

        let slots = MeetingPlannerService.recommendedSlots(
            participants: [p1, p2, p3, p4],
            localTimezoneId: "Asia/Shanghai",
            durationMinutes: 60,
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertEqual(slots.first?.tier, 0)
        XCTAssertEqual(slots.first?.workingCount, 4)

        let firstNonAll = try! XCTUnwrap(slots.first { $0.tier == 1 })
        XCTAssertEqual(firstNonAll.awakeCount, 1)
        XCTAssertEqual(shanghaiCalendar().component(.hour, from: firstNonAll.startDate), 11)

        let nineSlot = try! XCTUnwrap(slots.first { shanghaiCalendar().component(.hour, from: $0.startDate) == 9 })
        XCTAssertEqual(nineSlot.awakeCount, 2)
        let nineIndex = try! XCTUnwrap(slots.firstIndex { $0.id == nineSlot.id })
        let nonAllIndex = try! XCTUnwrap(slots.firstIndex { $0.id == firstNonAll.id })
        XCTAssertGreaterThan(nineIndex, nonAllIndex)
    }

    func testRecommendedSlotsSkipsPassedSlotsAndSpansDays() {
        // 17:00 时，当日 9:00 档期已过应被跳过；范围延伸至明日时应有明日档期
        let slots = MeetingPlannerService.recommendedSlots(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            durationMinutes: 60,
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai").addingTimeInterval(24 * 60 * 60),
            date: date(hour: 17, timezoneId: "Asia/Shanghai")
        )

        XCTAssertFalse(slots.isEmpty)
        let now = date(hour: 17, timezoneId: "Asia/Shanghai")
        XCTAssertTrue(slots.allSatisfy { $0.startDate > now })

        let tomorrowMorning = try! XCTUnwrap(
            slots.first {
                shanghaiCalendar().component(.hour, from: $0.startDate) == 9
                    && shanghaiCalendar().component(.day, from: $0.startDate) == 22
            }
        )
        XCTAssertEqual(shanghaiCalendar().component(.day, from: tomorrowMorning.startDate), 22)
    }

    func testRecommendedSlotsRejectsInvertedDateRange() {
        // 结束日期早于开始日期 → 无法生成
        let slots = MeetingPlannerService.recommendedSlots(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            durationMinutes: 60,
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai").addingTimeInterval(24 * 60 * 60),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )
        XCTAssertTrue(slots.isEmpty)
    }

    // MARK: - 重叠不足指标

    func testMaxOverlapMinutesAcrossDateRange() {
        // 上海+伦敦：16:00–18:00 全员工作 = 120 分钟
        let minutes = MeetingPlannerService.maxOverlapMinutes(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )
        XCTAssertEqual(minutes, 120)
    }

    func testMaxOverlapMinutesOnlyCountsFuture() {
        // 16:30 时，16:00–16:30 已过；剩余未来重叠 17:00–18:00 = 60 分钟
        let minutes = MeetingPlannerService.maxOverlapMinutes(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 16, minute: 30, timezoneId: "Asia/Shanghai")
        )
        XCTAssertEqual(minutes, 60)
    }

    func testMaxOverlapMinutesZeroWhenNoOverlap() {
        // 上海+洛杉矶+伦敦当日无全员交集
        let minutes = MeetingPlannerService.maxOverlapMinutes(
            participants: [shanghai, losAngeles, london],
            localTimezoneId: "Asia/Shanghai",
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )
        XCTAssertEqual(minutes, 0)
    }

    func testConstraintParticipantsIdentifiesBoundaryCities() {
        // 上海 9–18、伦敦（上海轴 16–次日 1）→ 最长重叠 16–18：
        // 伦敦 16:00 上班限制开始，上海 18:00 下班限制结束
        let constraints = MeetingPlannerService.constraintParticipants(
            participants: [shanghai, london],
            localTimezoneId: "Asia/Shanghai",
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )

        XCTAssertEqual(constraints.count, 2)
        XCTAssertEqual(constraints.first { $0.participant.id == london.id }?.kind, .start)
        XCTAssertEqual(constraints.first { $0.participant.id == shanghai.id }?.kind, .end)
    }

    func testConstraintParticipantsEmptyWhenNoOverlap() {
        let constraints = MeetingPlannerService.constraintParticipants(
            participants: [shanghai, losAngeles, london],
            localTimezoneId: "Asia/Shanghai",
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 12, timezoneId: "Asia/Shanghai")
        )
        XCTAssertTrue(constraints.isEmpty)
    }

    // MARK: - 档期合并

    func testSlotGroupsMergeAdjacentSameProfile() {
        let d0 = date(hour: 16, timezoneId: "Asia/Shanghai")
        let d1 = date(hour: 16, minute: 30, timezoneId: "Asia/Shanghai")
        let d2 = date(hour: 17, timezoneId: "Asia/Shanghai")
        let slots = [
            MeetingSlot(startDate: d0, durationMinutes: 30, workingCount: 2, awakeCount: 0, sleepingCount: 0, tier: 0),
            MeetingSlot(startDate: d1, durationMinutes: 30, workingCount: 2, awakeCount: 0, sleepingCount: 0, tier: 0),
            MeetingSlot(startDate: d2, durationMinutes: 30, workingCount: 2, awakeCount: 0, sleepingCount: 0, tier: 0)
        ]

        let groups = MeetingPlannerService.slotGroups(from: slots)

        XCTAssertEqual(groups.count, 1)
        let group = try! XCTUnwrap(groups.first)
        XCTAssertEqual(group.startDate, d0)
        XCTAssertEqual(group.endDate, date(hour: 17, minute: 30, timezoneId: "Asia/Shanghai"))
        XCTAssertEqual(group.durationMinutes, 30)
        XCTAssertEqual(group.tier, 0)
        XCTAssertEqual(group.optionStartDates, [d0, d1, d2])
    }

    func testSlotGroupsSplitByDifferentProfile() {
        let d0 = date(hour: 16, timezoneId: "Asia/Shanghai")
        let d1 = date(hour: 16, minute: 30, timezoneId: "Asia/Shanghai")
        let slots = [
            MeetingSlot(startDate: d0, durationMinutes: 30, workingCount: 2, awakeCount: 0, sleepingCount: 0, tier: 0),
            MeetingSlot(startDate: d1, durationMinutes: 30, workingCount: 1, awakeCount: 1, sleepingCount: 0, tier: 1)
        ]

        let groups = MeetingPlannerService.slotGroups(from: slots)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].tier, 0)
        XCTAssertEqual(groups[0].optionStartDates, [d0])
        XCTAssertEqual(groups[1].tier, 1)
        XCTAssertEqual(groups[1].optionStartDates, [d1])
    }

    func testSlotGroupsDoNotMergeAcrossGap() {
        let d0 = date(hour: 16, timezoneId: "Asia/Shanghai")
        let d1 = date(hour: 17, timezoneId: "Asia/Shanghai")
        let slots = [
            MeetingSlot(startDate: d0, durationMinutes: 30, workingCount: 2, awakeCount: 0, sleepingCount: 0, tier: 0),
            MeetingSlot(startDate: d1, durationMinutes: 30, workingCount: 2, awakeCount: 0, sleepingCount: 0, tier: 0)
        ]

        let groups = MeetingPlannerService.slotGroups(from: slots)

        XCTAssertEqual(groups.count, 2)
    }

    func testSlotGroupsEmptyInputReturnsEmpty() {
        XCTAssertTrue(MeetingPlannerService.slotGroups(from: []).isEmpty)
    }

    // MARK: - 整段会议区间状态

    func testStateOverIntervalEndingAfterWorkHoursIsOffWork() {
        let seoul = MeetingParticipant(
            id: "sel",
            cityName: "Seoul",
            cityEn: "Seoul",
            timezoneId: "Asia/Seoul",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: false
        )
        // 17:30–18:30：开始在工作时间内，但 18:00–18:30 已下班 → 非工作时间
        let start = date(hour: 17, minute: 30, timezoneId: "Asia/Seoul")
        let end = date(hour: 18, minute: 30, timezoneId: "Asia/Seoul")
        XCTAssertEqual(
            MeetingPlannerService.state(of: seoul, from: start, to: end),
            .awake
        )
    }

    func testStateOverIntervalFullyWithinWorkHoursIsWorking() {
        let seoul = MeetingParticipant(
            id: "sel",
            cityName: "Seoul",
            cityEn: "Seoul",
            timezoneId: "Asia/Seoul",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: false
        )
        let start = date(hour: 14, timezoneId: "Asia/Seoul")
        let end = date(hour: 15, timezoneId: "Asia/Seoul")
        XCTAssertEqual(
            MeetingPlannerService.state(of: seoul, from: start, to: end),
            .working
        )
    }

    func testStateOverIntervalTouchingSleepIsSleeping() {
        let seoul = MeetingParticipant(
            id: "sel",
            cityName: "Seoul",
            cityEn: "Seoul",
            timezoneId: "Asia/Seoul",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: false
        )
        // 06:30–07:30：跨过 07:00 起床点 → 睡眠
        let start = date(hour: 6, minute: 30, timezoneId: "Asia/Seoul")
        let end = date(hour: 7, minute: 30, timezoneId: "Asia/Seoul")
        XCTAssertEqual(
            MeetingPlannerService.state(of: seoul, from: start, to: end),
            .sleeping
        )
    }

    func testRecommendedSlotsNotAllWorkingWhenMeetingExtendsPastWorkEnd() {
        let beijing = MeetingParticipant(
            id: "bj",
            cityName: "Beijing",
            cityEn: "Beijing",
            timezoneId: "Asia/Shanghai",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: true
        )
        let seoul = MeetingParticipant(
            id: "sel",
            cityName: "Seoul",
            cityEn: "Seoul",
            timezoneId: "Asia/Seoul",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: false
        )
        let slots = MeetingPlannerService.recommendedSlots(
            participants: [beijing, seoul],
            localTimezoneId: "Asia/Shanghai",
            durationMinutes: 60,
            startDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            endDate: date(hour: 0, timezoneId: "Asia/Shanghai"),
            date: date(hour: 0, timezoneId: "Asia/Shanghai")
        )

        // 09:00 北京 = 10:00–11:00 首尔，全程在工作时间内 → 全员可开会
        let allWorking = slots.first { $0.tier == 0 }
        XCTAssertEqual(allWorking?.startDate, date(hour: 9, timezoneId: "Asia/Shanghai"))
        // 16:30 北京 = 17:30–18:30 首尔，超出下班时间 → 不能算全员可开会
        let lateSlot = slots.first { $0.startDate == date(hour: 16, minute: 30, timezoneId: "Asia/Shanghai") }
        XCTAssertEqual(lateSlot?.tier, 1)
        XCTAssertEqual(lateSlot?.awakeCount, 1)
    }

    @MainActor
    func testSlotDetailDayPrefixUsesCalendarDay() {
        let beijing = MeetingParticipant(
            id: "bj",
            cityName: "Beijing",
            cityEn: "Beijing",
            timezoneId: "Asia/Shanghai",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: true
        )
        let calgary = MeetingParticipant(
            id: "yyc",
            cityName: "Calgary",
            cityEn: "Calgary",
            timezoneId: "America/Edmonton",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: false
        )
        let seoul = MeetingParticipant(
            id: "sel",
            cityName: "Seoul",
            cityEn: "Seoul",
            timezoneId: "Asia/Seoul",
            workStartHour: 9,
            workEndHour: 18,
            isLocal: false
        )
        let viewModel = MeetingViewModel()
        viewModel.participants = [beijing, calgary, seoul]
        viewModel.selectedIDs = ["bj", "yyc", "sel"]
        viewModel.localTimezoneId = "Asia/Shanghai"

        let start = date(hour: 16, minute: 30, timezoneId: "Asia/Shanghai")
        let detail = viewModel.slotDetail(startDate: start, durationMinutes: 60, use24Hour: true)

        // 北京 16:30 时：卡尔加里同日 02:30、首尔同日 17:30，均不应出现「昨日/次日」前缀
        XCTAssertEqual(detail.rows.first { $0.id == "bj" }?.timeText, "16:30 – 17:30")
        XCTAssertEqual(detail.rows.first { $0.id == "yyc" }?.timeText, "02:30 – 03:30")
        XCTAssertEqual(detail.rows.first { $0.id == "sel" }?.timeText, "17:30 – 18:30")
        // 首尔 17:30–18:30 已跨过 18:00 下班时间 → 非工作时间
        XCTAssertEqual(detail.rows.first { $0.id == "sel" }?.state, .awake)
    }
}
