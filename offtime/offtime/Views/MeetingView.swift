import SwiftUI
import SwiftData

/// 多时区会议规划：勾选城市 + 设置时长与会议日期 → 自动按各城市工作时间生成推荐档期 → 加入会议列表。
struct MeetingView: View {
    @Binding var activeTab: AppTab
    @StateObject private var viewModel = MeetingViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastSeenCitiesRevision: Int = 0
    @State private var selectedGroup: MeetingSlotGroup?
    @State private var toastMessage: String?
    @State private var showConflictAlert = false
    @State private var conflictMeetingID: UUID?
    @State private var showMeetingRecords = false
    @State private var highlightedMeetingID: UUID?

    private let timezoneService = TimezoneService.shared

    private var use24Hour: Bool {
        appEnvironment.settings.use24Hour
    }

    /// 会议页与时钟页共享同一套分钟时钟；两页均视为「活跃域」，
    /// 由各自 onAppear/onChange 校正启停（start/stop 均幂等，无竞争）。
    private var shouldRunTimer: Bool {
        scenePhase == .active && (activeTab == .clock || activeTab == .meeting)
    }

    private func updateTimer() {
        if shouldRunTimer {
            appEnvironment.startMinuteClock()
        } else {
            appEnvironment.stopMinuteClock()
        }
    }

    private func loadParticipants() {
        let localTimezoneId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
        viewModel.loadParticipants(
            localTimezoneId: localTimezoneId,
            localCityName: appEnvironment.settings.currentCityName,
            localCityEn: appEnvironment.settings.currentCityEn
        )
        lastSeenCitiesRevision = appEnvironment.citiesRevision
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    participantsCard
                    settingsCard
                    overlapCard
                    slotsCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "tab.meeting"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadParticipants()
                updateTimer()
            }
            .onChange(of: activeTab) { _, newValue in
                updateTimer()
                if newValue == .meeting {
                    loadParticipants()
                }
            }
            .onChange(of: scenePhase) { _, _ in
                updateTimer()
            }
            .onChange(of: appEnvironment.citiesRevision) { _, newValue in
                if lastSeenCitiesRevision != newValue {
                    loadParticipants()
                }
            }
            .onChange(of: appEnvironment.settings.currentCityTimezoneId) { _, _ in
                loadParticipants()
            }
            .onReceive(appEnvironment.$currentDate) { date in
                viewModel.currentDate = date
            }
        }
        .sheet(item: $selectedGroup) { group in
            SlotDetailSheet(
                rangeText: groupRangeText(group),
                group: group,
                meetingDate: viewModel.meetingDate,
                use24Hour: use24Hour,
                localTimezoneId: viewModel.localTimezoneId,
                makeDetail: { startDate in
                    viewModel.slotDetail(
                        startDate: startDate,
                        durationMinutes: group.durationMinutes,
                        use24Hour: use24Hour
                    )
                },
                onAdd: { startDate in
                    if addMeeting(startDate: startDate, durationMinutes: group.durationMinutes) {
                        selectedGroup = nil
                    }
                }
            )
            .alert(
                String(localized: "meeting.add.conflict.title"),
                isPresented: $showConflictAlert
            ) {
                Button(String(localized: "meeting.add.conflict.view")) {
                    guard let conflictMeetingID else { return }
                    selectedGroup = nil
                    highlightedMeetingID = conflictMeetingID
                    showMeetingRecords = true
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "meeting.add.conflict"))
            }
        }
        .toast(message: $toastMessage)
        .fullScreenCover(isPresented: $showMeetingRecords) {
            NavigationStack {
                MeetingListView(highlightMeetingID: highlightedMeetingID)
            }
        }
    }

    @discardableResult
    private func addMeeting(startDate: Date, durationMinutes: Int) -> Bool {
        let endDate = startDate.addingTimeInterval(Double(durationMinutes) * 60)
        let existing = (try? modelContext.fetch(FetchDescriptor<MeetingModel>())) ?? []
        if let conflict = existing.first(where: { meeting in
            let meetingEnd = meeting.startDate.addingTimeInterval(Double(meeting.durationMinutes) * 60)
            return startDate < meetingEnd && meeting.startDate < endDate
        }) {
            conflictMeetingID = conflict.id
            showConflictAlert = true
            return false
        }
        let meeting = MeetingModel(
            startDate: startDate,
            durationMinutes: durationMinutes,
            localTimezoneId: viewModel.localTimezoneId,
            participantNames: viewModel.participantNames,
            participantEnNames: viewModel.participantEnNames
        )
        modelContext.insert(meeting)
        try? modelContext.save()
        viewModel.saveSelectedParticipantIDs()
        toastMessage = String(localized: "meeting.add.success")
        return true
    }

    // MARK: - 参与者卡片

    private var participantsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "meeting.participants.title"))
                        .font(.headline)
                    Text(String(localized: "meeting.participants.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(viewModel.participants) { participant in
                        participantRow(participant)
                        if participant.id != viewModel.participants.last?.id {
                            Divider()
                        }
                    }
                }

                if viewModel.participants.count <= 1 {
                    Text(String(localized: "meeting.participants.hint"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func participantRow(_ participant: MeetingParticipant) -> some View {
        let isSelected = viewModel.selectedIDs.contains(participant.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.toggleParticipant(participant)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(CityDisplay.primaryName(cityName: participant.cityName, cityEn: participant.cityEn))
                            .font(.body.weight(.medium))
                        if participant.isLocal {
                            Text(String(localized: "meeting.local.badge"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    if let secondary = CityDisplay.secondaryName(cityName: participant.cityName, cityEn: participant.cityEn) {
                        Text("\(secondary) · \(currentTimeText(for: participant))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(currentTimeText(for: participant))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private func currentTimeText(for participant: MeetingParticipant) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: participant.timezoneId, date: viewModel.currentDate) ?? ""
        }
        return timezoneService.getLocalTime12(timezoneId: participant.timezoneId, date: viewModel.currentDate) ?? ""
    }

    // MARK: - 会议设置卡片

    private var settingsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "meeting.settings.duration"))
                        .font(.headline)
                    Picker(String(localized: "meeting.settings.duration"), selection: $viewModel.durationMinutes) {
                        ForEach([30, 60, 90, 120], id: \.self) { minutes in
                            Text(String(format: String(localized: "meeting.settings.duration.format"), minutes))
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.accentColor)
                }

                HStack(spacing: 12) {
                    Text(String(localized: "meeting.settings.range"))
                        .font(.headline)
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(viewModel.dateOptions, id: \.self) { option in
                            Button(dateLabel(option)) {
                                viewModel.meetingDate = option
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                            Text(dateLabel(viewModel.meetingDate))
                                .font(.body.weight(.semibold))
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    /// 日期显示：今天/明天显示特殊文案，其余按「月 日 周几」展示。
    private func dateLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: viewModel.localTimezoneId) ?? .current
        let today = calendar.startOfDay(for: viewModel.currentDate)
        let dayDiff = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        if dayDiff == 0 {
            return String(localized: "meeting.date.today")
        }
        if dayDiff == 1 {
            return String(localized: "meeting.date.tomorrow")
        }
        var style = Date.FormatStyle.dateTime.month(.defaultDigits).day().weekday(.abbreviated)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    // MARK: - 推荐档期卡片

    private var slotsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "meeting.slots.title"))
                        .font(.headline)
                    Text(String(localized: "meeting.slots.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if viewModel.selectedParticipants.count >= 2,
                   viewModel.maxOverlapMinutes < viewModel.durationMinutes {
                    insufficientOverlapNotice
                }

                if viewModel.slotGroups.isEmpty {
                    Text(String(localized: "meeting.slots.empty"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.slotGroups) { group in
                            slotGroupRow(group)
                        }
                    }
                }
            }
        }
    }

    /// 全员重叠不足会议时长时的提示：无重叠 / 重叠不足 + 建议。
    private var insufficientOverlapNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.maxOverlapMinutes == 0 {
                Text(String(localized: "meeting.slots.overlap.none"))
                    .font(.subheadline.weight(.medium))
                Text(String(localized: "meeting.slots.overlap.none.suggest"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(String(format: String(localized: "meeting.slots.overlap.short"), viewModel.maxOverlapMinutes))
                    .font(.subheadline.weight(.medium))
                if !viewModel.constraints.isEmpty {
                    Text(String(format: String(localized: "meeting.slots.overlap.constraints"), constraintText))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(String(format: String(localized: "meeting.slots.overlap.short.suggest"), viewModel.maxOverlapMinutes))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
    }

    private var constraintText: String {
        let parts = viewModel.constraints.map { constraint -> String in
            let hour = constraint.kind == .start
                ? constraint.participant.workStartHour
                : constraint.participant.workEndHour
            let time = String(format: "%02d:00", hour)
            let name = CityDisplay.primaryName(cityName: constraint.participant.cityName, cityEn: constraint.participant.cityEn)
            if constraint.kind == .start {
                return String(format: String(localized: "meeting.slots.constraint.start"), name, time)
            }
            return String(format: String(localized: "meeting.slots.constraint.end"), name, time)
        }
        return parts.joined(separator: String(localized: "meeting.slots.constraints.join"))
    }

    private func slotGroupRow(_ group: MeetingSlotGroup) -> some View {
        Button {
            selectedGroup = group
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupRangeText(group))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Spacer(minLength: 0)
                slotTierBadge(group)
                Text(String(localized: "meeting.slots.view"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.systemGray3))
                    .fixedSize()
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6).opacity(0.55))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
    }

    private func slotTierBadge(_ group: MeetingSlotGroup) -> some View {
        let text: String
        let color: Color
        switch group.tier {
        case 0:
            text = String(localized: "meeting.slots.tier.all")
            color = .green
        case 1:
            text = String(format: String(localized: "meeting.slots.tier.adjust"), group.awakeCount)
            color = .orange
        default:
            text = String(format: String(localized: "meeting.slots.tier.sleeping"), group.sleepingCount)
            color = Color(.systemGray)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .cornerRadius(6)
    }

    // MARK: - 全天工作重叠卡片

    private var overlapCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(localized: "meeting.overlap.title"))
                        .font(.headline)
                    Spacer(minLength: 8)
                    if viewModel.selectedParticipants.count >= 2 {
                        overlapStatusLabel
                    }
                }
                Text(String(localized: "meeting.overlap.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if viewModel.selectedParticipants.count < 2 {
                    Text(String(localized: "meeting.overlap.hint"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.selectedParticipants) { participant in
                            HStack(spacing: 10) {
                                Text(CityDisplay.primaryName(cityName: participant.cityName, cityEn: participant.cityEn))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 76, alignment: .leading)
                                    .lineLimit(1)
                                HoursBar(
                                    hours: viewModel.workingHours(for: participant),
                                    color: .blue.opacity(0.75),
                                    markerHour: nil
                                )
                            }
                        }

                        Divider()

                        HStack(spacing: 10) {
                            Text(String(localized: "meeting.overlap.all"))
                                .font(.caption.weight(.semibold))
                                .frame(width: 76, alignment: .leading)
                            HoursBar(
                                hours: viewModel.overlap.hourlyOverlap,
                                color: .green,
                                markerHour: viewModel.overlap.currentLocalHour
                            )
                        }

                        hourScaleRow
                    }
                }
            }
        }
    }

    private var overlapStatusLabel: some View {
        let overlap = viewModel.overlap
        if overlap.isCurrentlyOverlapping {
            return Text(String(localized: "meeting.overlap.now"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)
        }
        if let next = viewModel.nextWindow {
            return Text("\(String(localized: "meeting.overlap.next")) \(nextWindowText(next))")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        return Text(String(localized: "meeting.overlap.none"))
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
    }

    private var hourScaleRow: some View {
        HStack(spacing: 10) {
            Text("")
                .frame(width: 76, alignment: .leading)
            hourScale
        }
    }

    /// 24 小时刻度：0/6/12/18 位于对应分段边界，24 贴右缘，与 HoursBar 的 24 个小段对齐
    private var hourScale: some View {
        let labels: [Int: String] = [0: "0", 6: "6", 12: "12", 18: "18", 23: "24"]
        return HStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { index in
                Text(labels[index] ?? "")
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: index == 23 ? .trailing : .leading)
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }

    // MARK: - 时间格式化

    /// 本地时间字符串（按用户 12/24 小时偏好）
    private func formatLocalTime(_ date: Date) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: viewModel.localTimezoneId, date: date) ?? ""
        }
        return timezoneService.getLocalTime12(timezoneId: viewModel.localTimezoneId, date: date) ?? ""
    }

    /// 相对今天的日期前缀：今天为空；明日为「明日」；更远的日子显示具体日期。
    private func dayPrefix(for date: Date) -> String {
        guard let localTimezone = TimeZone(identifier: viewModel.localTimezoneId) else {
            return ""
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = localTimezone
        let todayStart = calendar.dateInterval(of: .day, for: viewModel.currentDate)?.start ?? viewModel.currentDate
        let targetStart = calendar.dateInterval(of: .day, for: date)?.start ?? date
        let dayDiff = calendar.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0
        switch dayDiff {
        case ...0:
            return ""
        case 1:
            return String(localized: "clock.tomorrow")
        default:
            var style = Date.FormatStyle.dateTime.month(.defaultDigits).day().weekday(.abbreviated)
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
    }

    /// 档期时间段标题：本地起止时间（会议日期已由日期选择器展示，不再重复日期前缀）
    private func groupRangeText(_ group: MeetingSlotGroup) -> String {
        "\(formatLocalTime(group.startDate))–\(formatLocalTime(group.endDate))"
    }

    /// 下一个重叠窗口的开始时间，跨天带「明日」前缀
    private func nextWindowText(_ window: MeetingWindow) -> String {
        let time = formatLocalTime(window.startDate)
        let prefix = dayPrefix(for: window.startDate)
        return prefix.isEmpty ? time : "\(prefix) \(time)"
    }
}

// MARK: - 24 小时色条

private struct HoursBar: View {
    let hours: [Bool]
    let color: Color
    let markerHour: Double?

    var body: some View {
        Canvas { context, size in
            let segW = size.width / 24
            let height = size.height
            for hour in 0..<24 {
                let rect = CGRect(
                    x: CGFloat(hour) * segW,
                    y: 0,
                    width: max(segW - 1, 1),
                    height: height
                )
                let segmentColor = hours[hour] ? color : Color(.systemGray5)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(segmentColor))
            }
            if let markerHour {
                let x = CGFloat(markerHour) * segW
                let marker = CGRect(x: x - 1, y: -1.5, width: 2, height: height + 3)
                context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(.red))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - 档期详情弹层

private struct SlotDetailSheet: View {
    let rangeText: String
    let group: MeetingSlotGroup
    let meetingDate: Date
    let use24Hour: Bool
    let localTimezoneId: String
    let makeDetail: (Date) -> MeetingSlotDetail
    let onAdd: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStartDate: Date

    init(
        rangeText: String,
        group: MeetingSlotGroup,
        meetingDate: Date,
        use24Hour: Bool,
        localTimezoneId: String,
        makeDetail: @escaping (Date) -> MeetingSlotDetail,
        onAdd: @escaping (Date) -> Void
    ) {
        self.rangeText = rangeText
        self.group = group
        self.meetingDate = meetingDate
        self.use24Hour = use24Hour
        self.localTimezoneId = localTimezoneId
        self.makeDetail = makeDetail
        self.onAdd = onAdd
        _selectedStartDate = State(initialValue: group.optionStartDates.first ?? group.startDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if group.optionStartDates.count > 1 {
                    VStack(spacing: 8) {
                        Text(rangeText)
                            .font(.title2.weight(.bold))
                        VStack(spacing: 4) {
                            Text(String(localized: "meeting.detail.range.hint"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(8)
                    }
                    .padding(.top, 8)
                }

                if group.optionStartDates.count > 1 {
                    HStack {
                        Text(String(localized: "meeting.detail.select.start"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Menu {
                            ForEach(group.optionStartDates, id: \.self) { startDate in
                                Button(startTimeText(startDate)) {
                                    selectedStartDate = startDate
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(startTimeText(selectedStartDate))
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.accentColor)
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                VStack(spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(meetingDateString)
                            .font(.subheadline.weight(.bold))
                        Text(meetingTimeText(selectedStartDate))
                            .font(.title2.weight(.bold))
                    }
                    Text(String(localized: "meeting.detail.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                let detail = makeDetail(selectedStartDate)
                VStack(spacing: 0) {
                    ForEach(detail.rows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(CityDisplay.primaryName(cityName: row.cityName, cityEn: row.cityEn))
                                        .font(.body.weight(.medium))
                                    if row.isLocal {
                                        Text(String(localized: "meeting.local.badge"))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.15))
                                            .cornerRadius(4)
                                    }
                                }
                                if let secondary = CityDisplay.secondaryName(cityName: row.cityName, cityEn: row.cityEn) {
                                    Text(secondary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(row.timeText)
                                    .font(.body.weight(.semibold))
                                    .multilineTextAlignment(.trailing)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(stateColor(row.state))
                                        .frame(width: 6, height: 6)
                                    Text(stateLabel(row.state))
                                        .font(.caption)
                                        .foregroundColor(stateColor(row.state))
                                }
                            }
                        }
                        .padding(.vertical, 10)
                        if row.id != detail.rows.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)

                Button {
                    onAdd(selectedStartDate)
                } label: {
                    Label(String(localized: "meeting.detail.add"), systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "meeting.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
    }

    private func startTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: localTimezoneId) ?? .current
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    private func meetingTimeText(_ date: Date) -> String {
        let end = date.addingTimeInterval(Double(group.durationMinutes) * 60)
        return "\(startTimeText(date))–\(startTimeText(end))"
    }

    /// 会议日期格式化：2026-9-1 周二（按本地时区）
    private var meetingDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: localTimezoneId) ?? .current
        formatter.dateFormat = "yyyy/MM/dd EEE"
        return formatter.string(from: meetingDate)
    }

    private func stateColor(_ state: MeetingParticipantState) -> Color {
        switch state {
        case .working: return .green
        case .awake: return .orange
        case .sleeping: return Color(.systemGray)
        }
    }

    private func stateLabel(_ state: MeetingParticipantState) -> String {
        switch state {
        case .working: return String(localized: "meeting.state.working")
        case .awake: return String(localized: "meeting.state.offwork")
        case .sleeping: return String(localized: "meeting.state.sleeping")
        }
    }
}

// MARK: - 卡片容器

private struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 4)
    }
}

#Preview {
    MeetingView(activeTab: .constant(.meeting))
        .environmentObject(AppEnvironment())
}
