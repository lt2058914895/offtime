import SwiftUI
import SwiftData

private let meetingCardCornerRadius: CGFloat = 18

/// 已添加会议列表：展示从推荐档期加入的会议，支持滑动删除。
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Query(sort: \MeetingModel.startDate, order: .reverse) private var meetings: [MeetingModel]
    @State private var meetingToDelete: MeetingModel?
    @State private var statusFilter: MeetingStatus = .upcoming
    @State private var isAppeared = false
    @State private var sharePayload: MeetingSharePayload?
    let highlightMeetingID: UUID?

    init(highlightMeetingID: UUID? = nil) {
        self.highlightMeetingID = highlightMeetingID
    }

    private let timezoneService = TimezoneService.shared

    private enum MeetingStatus: String, CaseIterable, Identifiable {
        case upcoming, finished
        var id: String { rawValue }
    }

    /// 按天分组的会议 Section
    private struct MeetingDaySection: Identifiable {
        let id: Int
        let title: String
        let meetings: [MeetingModel]
    }

    private var use24Hour: Bool {
        appEnvironment.settings.use24Hour
    }

    private var now: Date {
        appEnvironment.currentDate
    }

    private var shouldRunMinuteClock: Bool {
        scenePhase == .active && isAppeared
    }

    var body: some View {
        Group {
            if meetings.isEmpty {
                ContentUnavailableView(
                    String(localized: "meeting.list.empty.title"),
                    systemImage: "calendar.badge.clock",
                    description: Text(String(localized: "meeting.list.empty"))
                )
            } else {
                VStack(spacing: 0) {
                    Picker(String(localized: "meeting.list.filter.title"), selection: $statusFilter) {
                        Text(String(localized: "meeting.list.filter.upcoming")).tag(MeetingStatus.upcoming)
                        Text(String(localized: "meeting.list.filter.finished")).tag(MeetingStatus.finished)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if sections.isEmpty {
                        ContentUnavailableView(
                            String(localized: "meeting.list.filter.empty"),
                            systemImage: "calendar"
                        )
                    } else {
                        List {
                            Text(String(localized: "meeting.list.hint"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)

                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.meetings) { meeting in
                                        row(for: meeting)
                                    }
                                } header: {
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                        .textCase(nil)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color(uiColor: .systemGroupedBackground))
                    }
                }
            }
        }
        .navigationTitle(String(localized: "meeting.list.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            isAppeared = true
            updateMinuteClock()
            if let highlightMeetingID,
               let meeting = meetings.first(where: { $0.id == highlightMeetingID }) {
                let end = meeting.startDate.addingTimeInterval(Double(meeting.durationMinutes) * 60)
                statusFilter = end > appEnvironment.currentDate ? .upcoming : .finished
            }
        }
        .onDisappear {
            isAppeared = false
            updateMinuteClock()
        }
        .onChange(of: scenePhase) { _, _ in
            updateMinuteClock()
        }
        .confirmationDialog(
            String(localized: "meeting.list.delete.confirm.title"),
            isPresented: Binding(
                get: { meetingToDelete != nil },
                set: { if !$0 { meetingToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: meetingToDelete
        ) { meeting in
            Button(String(localized: "meeting.list.delete"), role: .destructive) {
                modelContext.delete(meeting)
                try? modelContext.save()
                meetingToDelete = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                meetingToDelete = nil
            }
        } message: { meeting in
            Text(fullRangeText(for: meeting))
        }
        .sheet(item: $sharePayload) { payload in
            MeetingShareSheet(payload: payload)
        }
    }

    private var sections: [MeetingDaySection] {
        let isUpcoming = statusFilter == .upcoming
        var grouped: [Int: [MeetingModel]] = [:]
        for meeting in meetings {
            let end = meeting.startDate.addingTimeInterval(Double(meeting.durationMinutes) * 60)
            let included = isUpcoming ? end > now : end <= now
            guard included else { continue }
            grouped[dayKey(for: meeting), default: []].append(meeting)
        }
        return grouped.keys.sorted(by: isUpcoming ? { $0 < $1 } : { $0 > $1 }).compactMap { key in
            let items = grouped[key] ?? []
            guard let first = items.min(by: { $0.startDate < $1.startDate }) else { return nil }
            return MeetingDaySection(
                id: key,
                title: dateText(first.startDate, timezoneId: first.localTimezoneId),
                meetings: items.sorted(by: isUpcoming ? { $0.startDate < $1.startDate } : { $0.startDate > $1.startDate })
            )
        }
    }

    /// 会议开始时间在自身本地时区下的日历日序号（年月日，可比较排序）。
    private func dayKey(for meeting: MeetingModel) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: meeting.localTimezoneId) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: meeting.startDate)
        return (components.year ?? 0) * 10000 + (components.month ?? 0) * 100 + (components.day ?? 0)
    }

    private func row(for meeting: MeetingModel) -> some View {
        let end = meeting.startDate.addingTimeInterval(Double(meeting.durationMinutes) * 60)
        let isOngoing = meeting.startDate <= now && end > now
        let isFinished = end <= now
        let isHighlighted = meeting.id == highlightMeetingID
        let meetingDateTime = localDateTimeParts(
            start: meeting.startDate,
            end: end,
            timezoneId: meeting.localTimezoneId
        )
        let resolvedParticipants = participants(for: meeting)
        let duration = String(
            format: String(localized: "meeting.settings.duration.format"),
            meeting.durationMinutes
        )
        let cardBackground = isHighlighted
            ? Color.orange.opacity(0.16)
            : Color(uiColor: .secondarySystemGroupedBackground)
        let cardBorder = isHighlighted
            ? Color.orange.opacity(0.55)
            : Color(uiColor: .separator).opacity(0.18)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(meetingDateTime.time)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .layoutPriority(1)

                Text(duration)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isFinished ? .secondary : .accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isFinished ? Color.secondary : Color.accentColor).opacity(0.12))
                    .clipShape(Capsule())

                Spacer(minLength: 8)

                if isOngoing {
                    Text(String(localized: "meeting.list.ongoing"))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
            }

            if !resolvedParticipants.isEmpty {
                Divider()

                VStack(spacing: 8) {
                    ForEach(Array(resolvedParticipants.enumerated()), id: \.offset) { item in
                        cityTimeRow(item.element, start: meeting.startDate, end: end)
                    }
                }
            }
        }
        .opacity(isFinished ? 0.6 : 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: meetingCardCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: meetingCardCornerRadius, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: isHighlighted ? 1 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: meetingCardCornerRadius, style: .continuous))
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                meetingToDelete = meeting
            } label: {
                Label(String(localized: "meeting.list.delete"), systemImage: "trash")
            }
        }
        .onLongPressGesture {
            share(meeting)
        }
    }

    private func cityTimeRow(
        _ participant: MeetingCalendarParticipant,
        start: Date,
        end: Date
    ) -> some View {
        let cityName = CityDisplay.primaryName(
            cityName: participant.cityName,
            cityEn: participant.cityEn
        )
        let dateTime = participant.timezoneId.flatMap { timezoneId -> (date: String, time: String)? in
            guard TimeZone(identifier: timezoneId) != nil else { return nil }
            return localDateTimeParts(start: start, end: end, timezoneId: timezoneId)
        }

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(cityName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if let dateTime {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(dateTime.date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Text(dateTime.time)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(dateTime.date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)

                        Text(dateTime.time)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            } else {
                Text(verbatim: "—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func share(_ meeting: MeetingModel) {
        sharePayload = MeetingSharePayload(
            event: MeetingCalendarEvent(
                uid: meeting.id.uuidString,
                startDate: meeting.startDate,
                durationMinutes: meeting.durationMinutes,
                localTimezoneId: meeting.localTimezoneId,
                participants: participants(for: meeting)
            ),
            use24Hour: use24Hour
        )
    }

    private func participants(for meeting: MeetingModel) -> [MeetingCalendarParticipant] {
        let storedTimezoneIds = meeting.participantTimezoneIds ?? []
        if storedTimezoneIds.count == meeting.participantNames.count,
           storedTimezoneIds.allSatisfy({ TimeZone(identifier: $0) != nil }) {
            return meeting.participantNames.enumerated().map { index, cityName in
                MeetingCalendarParticipant(
                    cityName: cityName,
                    cityEn: index < meeting.participantEnNames.count
                        ? meeting.participantEnNames[index]
                        : cityName,
                    timezoneId: storedTimezoneIds[index]
                )
            }
        }

        let savedCities = (try? CityService.shared.getAllCities())?.map {
            MeetingCityTimezoneCandidate(
                cityName: $0.cityName,
                cityEn: $0.cityEn,
                timezoneId: $0.timezoneId
            )
        } ?? []
        let catalogCities = (CityService.allCities() ?? []).map {
            MeetingCityTimezoneCandidate(
                cityName: $0.cityName,
                cityEn: $0.cityEn,
                timezoneId: $0.timezoneId
            )
        }
        let localNames = CityService.matchCity(for: meeting.localTimezoneId)
        let normalizedLocalEnglishName = CityIdentity.normalizedEnglishName(localNames.en)

        return meeting.participantNames.enumerated().map { index, cityName in
            let cityEn = index < meeting.participantEnNames.count
                ? meeting.participantEnNames[index]
                : cityName
            let storedTimezoneId = index < storedTimezoneIds.count
                ? storedTimezoneIds[index]
                : nil
            let validStoredTimezoneId = storedTimezoneId.flatMap {
                TimeZone(identifier: $0) != nil ? $0 : nil
            }
            let normalizedEnglishName = CityIdentity.normalizedEnglishName(cityEn)
            let isLocalParticipant = cityName == localNames.name ||
                (!normalizedEnglishName.isEmpty &&
                    normalizedEnglishName == normalizedLocalEnglishName)
            let preferredTimezoneId = isLocalParticipant ? meeting.localTimezoneId : nil

            let resolvedTimezoneId = validStoredTimezoneId
                ?? MeetingCityTimezoneResolver.timezoneId(
                    cityName: cityName,
                    cityEn: cityEn,
                    candidates: savedCities,
                    preferredTimezoneId: preferredTimezoneId
                )
                ?? MeetingCityTimezoneResolver.timezoneId(
                    cityName: cityName,
                    cityEn: cityEn,
                    candidates: catalogCities,
                    preferredTimezoneId: preferredTimezoneId
                )

            return MeetingCalendarParticipant(
                cityName: cityName,
                cityEn: cityEn,
                timezoneId: resolvedTimezoneId
            )
        }
    }

    private func fullRangeText(for meeting: MeetingModel) -> String {
        let end = meeting.startDate.addingTimeInterval(Double(meeting.durationMinutes) * 60)
        let dateTime = localDateTimeParts(
            start: meeting.startDate,
            end: end,
            timezoneId: meeting.localTimezoneId
        )
        return "\(dateTime.date) \(dateTime.time)"
    }

    private func localDateTimeParts(
        start: Date,
        end: Date,
        timezoneId: String
    ) -> (date: String, time: String) {
        let timeRange = "\(timeText(start, timezoneId: timezoneId))–\(timeText(end, timezoneId: timezoneId))"
        let startDate = dateText(start, timezoneId: timezoneId)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneId) ?? .current
        guard !calendar.isDate(start, inSameDayAs: end) else {
            return (startDate, timeRange)
        }

        let endDate = dateText(end, timezoneId: timezoneId)
        return ("\(startDate) – \(endDate)", timeRange)
    }

    private func timeText(_ date: Date, timezoneId: String) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: timezoneId, date: date) ?? ""
        }
        return timezoneService.getLocalTime12(timezoneId: timezoneId, date: date) ?? ""
    }

    private func dateText(_ date: Date, timezoneId: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: timezoneId) ?? .current
        formatter.dateFormat = "yyyy/MM/dd EEE"
        return formatter.string(from: date)
    }

    private func updateMinuteClock() {
        if shouldRunMinuteClock {
            appEnvironment.startMinuteClock()
        } else {
            appEnvironment.stopMinuteClock()
        }
    }

}

#Preview {
    MeetingListView()
        .environmentObject(AppEnvironment())
}
