import SwiftUI
import SwiftData

/// 多时区会议规划：勾选城市 + 设置时长与会议日期 → 自动按各城市工作时间生成推荐档期 → 加入会议列表。
struct MeetingView: View {
    @StateObject private var viewModel = MeetingViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var lastSeenCitiesRevision: Int = 0
    @State private var selectedGroup: MeetingSlotGroup?
    @State private var toastMessage: String?
    @State private var showConflictAlert = false
    @State private var conflictMeetingID: UUID?
    @State private var showMeetingRecords = false
    @State private var highlightedMeetingID: UUID?
    @State private var isAppeared = false
    var embedsNavigationStack: Bool = true

    private let timezoneService = TimezoneService.shared

    private var use24Hour: Bool {
        appEnvironment.settings.use24Hour
    }

    /// 页面可见且 App 在前台时刷新分钟级时间。
    private var shouldRunTimer: Bool {
        scenePhase == .active && isAppeared
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

    private var meetingContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                participantOverlapCard
                settingsCard
                slotsCard
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "settings.meeting.recommendation.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(String(localized: "meeting.recommendation.records")) {
                    highlightedMeetingID = nil
                    showMeetingRecords = true
                }
            }
        }
        .onAppear {
            isAppeared = true
            loadParticipants()
            updateTimer()
        }
        .onDisappear {
            isAppeared = false
            updateTimer()
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
            viewModel.updateCurrentDate(date)
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
            .presentationDetents([.large])
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

    var body: some View {
        if embedsNavigationStack {
            NavigationStack {
                meetingContent
            }
        } else {
            meetingContent
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

    // MARK: - 参与者与工作时段重叠卡片

    private var participantOverlapCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(localized: "meeting.participants.title"))
                        .font(.headline)
                }
                Text(String(localized: "meeting.participants.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    ForEach(viewModel.participants) { participant in
                        participantChip(participant)
                    }
                }

                if viewModel.selectedParticipants.count > 1 {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(localized: "meeting.overlap.all"))
                                .font(.headline)
                            Spacer(minLength: 8)
                            overlapStatusLabel
                        }
                        if viewModel.overlap.hourlyOverlap.contains(true) {
                            Text(String(localized: "meeting.overlap.subtitle"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(String(localized: "meeting.overlap.subtitle.none"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HoursBar(
                            hours: viewModel.overlap.hourlyOverlap,
                            color: .green,
                            markerHour: viewModel.overlap.currentLocalHour
                        )
                        hourScale
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

    private func participantChip(_ participant: MeetingParticipant) -> some View {
        let isSelected = viewModel.selectedIDs.contains(participant.id)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                viewModel.toggleParticipant(participant)
            }
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray3))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(CityDisplay.primaryName(cityName: participant.cityName, cityEn: participant.cityEn))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        if participant.isLocal {
                            Text(String(localized: "meeting.local.badge"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }

                        Spacer(minLength: 0)

                        dayNightBadge(for: participant)
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text("\(String(localized: "meeting.work.hours")): \(workingHoursText(for: participant))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayNightBadge(for participant: MeetingParticipant) -> some View {
        let isDaytime = isDaytime(for: participant)
        return Text(currentTimeText(for: participant))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isDaytime ? Color(red: 110 / 255.0, green: 168 / 255.0, blue: 220 / 255.0) : Color(red: 23 / 255.0, green: 55 / 255.0, blue: 94 / 255.0))
        .foregroundColor(.white)
        .clipShape(Capsule())
        .accessibilityLabel(String(localized: isDaytime ? "accessibility.daytime" : "accessibility.nighttime"))
    }

    private func isDaytime(for participant: MeetingParticipant) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: participant.timezoneId) ?? .current
        let hour = calendar.component(.hour, from: viewModel.currentDate)
        return hour >= 6 && hour < 18
    }

    private func workingHoursText(for participant: MeetingParticipant) -> String {
        String(format: "%02d:00–%02d:00", participant.workStartHour, participant.workEndHour)
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

    private func slotGroupRow(_ group: MeetingSlotGroup) -> some View {
        Button {
            selectedGroup = group
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(groupStartRangeText(group))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(2)

                    Text(String(
                        format: String(localized: "meeting.slots.start.meta"),
                        group.optionStartDates.count,
                        group.durationMinutes
                    ))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                }
                Spacer(minLength: 0)
                slotTierBadge(group)
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
            text = String(format: String(localized: "meeting.slots.tier.offwork"), group.awakeCount)
            color = .orange
        default:
            text = String(format: String(localized: "meeting.slots.tier.sleeping"), group.sleepingCount)
            color = Color(.systemGray)
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(.center)
            .layoutPriority(-1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .cornerRadius(6)
    }

    private var overlapStatusLabel: some View {
        let overlap = viewModel.overlap
        if overlap.isCurrentlyOverlapping {
            return Text(String(localized: "meeting.overlap.now"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.green)
        }
        if overlap.hourlyOverlap.contains(true) {
            return Text(String(localized: "meeting.overlap.available"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        return Text(String(localized: "meeting.overlap.none"))
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
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

    /// 档期状态时段标题：展示状态持续的本地起止区间
    private func groupRangeText(_ group: MeetingSlotGroup) -> String {
        return "\(formatLocalTime(group.startDate))–\(formatLocalTime(group.endDate))"
    }

    private func groupStartRangeText(_ group: MeetingSlotGroup) -> String {
        return groupRangeText(group)
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
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(segmentColor))
            }
            if let markerHour {
                let x = CGFloat(markerHour) * segW
                let marker = CGRect(x: x - 1, y: -2, width: 2, height: height + 4)
                context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(.red))
            }
        }
        .frame(height: 14)
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
            ScrollView {
                VStack(spacing: 12) {
                    overviewCard
                    selectedTimeCard
                    cityTimeCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                addButton
            }
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

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(rangeText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                statusBadge
            }

            if group.optionStartDates.count > 1 {
                startTimeSelector
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var selectedTimeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meetingDateString)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Text(meetingTimeText(selectedStartDate))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: String(localized: "meeting.detail.duration"), group.durationMinutes))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var startTimeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "meeting.detail.select.start"))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            StartTimeFlowLayout(spacing: 8) {
                ForEach(group.optionStartDates, id: \.self) { startDate in
                    let isSelected = startDate == selectedStartDate
                    Button {
                        selectedStartDate = startDate
                    } label: {
                        Text(startTimeText(startDate))
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var cityTimeCard: some View {
        let detail = makeDetail(selectedStartDate)
        return VStack(spacing: 0) {
            Text(String(localized: "meeting.detail.subtitle"))
                .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ForEach(detail.rows) { row in
                cityRow(row)
                if row.id != detail.rows.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func cityRow(_ row: MeetingSlotRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(CityDisplay.primaryName(cityName: row.cityName, cityEn: row.cityEn))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if row.isLocal {
                        Text(String(localized: "meeting.local.badge"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if let secondary = CityDisplay.secondaryName(cityName: row.cityName, cityEn: row.cityEn) {
                    Text(secondary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(row.timeText)
                    .font(.body.weight(.bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)

                Text(stateLabel(row.state))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(stateColor(row.state))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(stateColor(row.state).opacity(0.13))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusBadge: some View {
        let text: String
        let color: Color
        switch group.tier {
        case 0:
            text = String(localized: "meeting.slots.tier.all")
            color = .green
        case 1:
            text = String(format: String(localized: "meeting.slots.tier.offwork"), group.awakeCount)
            color = .orange
        default:
            text = String(format: String(localized: "meeting.slots.tier.sleeping"), group.sleepingCount)
            color = Color(.systemGray)
        }

        return Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var addButton: some View {
        Button {
            onAdd(selectedStartDate)
        } label: {
            Text(String(localized: "meeting.detail.add"))
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
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

private struct StartTimeFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }

        let height = subviews.isEmpty ? 0 : y + rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    MeetingView()
        .environmentObject(AppEnvironment())
}
