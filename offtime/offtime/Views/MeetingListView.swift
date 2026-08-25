import SwiftUI
import SwiftData
import Combine

/// 已添加会议列表：展示从推荐档期加入的会议，支持滑动删除。
struct MeetingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Query(sort: \MeetingModel.startDate, order: .reverse) private var meetings: [MeetingModel]
    @State private var meetingToDelete: MeetingModel?
    @State private var statusFilter: MeetingStatus = .upcoming
    @State private var now = Date()
    let highlightMeetingID: UUID?

    init(highlightMeetingID: UUID? = nil) {
        self.highlightMeetingID = highlightMeetingID
    }

    private let timezoneService = TimezoneService.shared
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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
                            Section {
                            } header: {
                                Text(String(localized: "meeting.list.swipe.hint"))
                                    .font(.caption2)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                    .textCase(nil)
                            }
                            ForEach(sections) { section in
                                Section {
                                    ForEach(section.meetings) { meeting in
                                        row(for: meeting)
                                    }
                                    .onDelete { offsets in
                                        guard let first = offsets.first else { return }
                                        meetingToDelete = section.meetings[first]
                                    }
                                } header: {
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                        .textCase(nil)
                                }
                            }
                        }
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
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            now = Date()
            if let highlightMeetingID,
               let meeting = meetings.first(where: { $0.id == highlightMeetingID }) {
                let end = meeting.startDate.addingTimeInterval(Double(meeting.durationMinutes) * 60)
                statusFilter = end > now ? .upcoming : .finished
            }
        }
        .onReceive(refreshTimer) { _ in
            now = Date()
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

        return HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundColor(isFinished ? Color(.systemGray) : .accentColor)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(timeRangeText(for: meeting))
                        .font(.body.weight(.semibold))
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
                Text(subtitle(for: meeting))
                    .font(.caption)
                    .foregroundColor(isFinished ? Color(.systemGray) : .secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isFinished ? 0.6 : 1)
        .listRowBackground(isHighlighted ? Color.orange.opacity(0.18) : nil)
    }

    private func timeRangeText(for meeting: MeetingModel) -> String {
        let start = meeting.startDate
        let end = start.addingTimeInterval(Double(meeting.durationMinutes) * 60)
        let startText = timeText(start, timezoneId: meeting.localTimezoneId)
        let endText = timeText(end, timezoneId: meeting.localTimezoneId)
        return "\(startText)–\(endText)"
    }

    private func fullRangeText(for meeting: MeetingModel) -> String {
        let date = dateText(meeting.startDate, timezoneId: meeting.localTimezoneId)
        return "\(date) \(timeRangeText(for: meeting))"
    }

    private func subtitle(for meeting: MeetingModel) -> String {
        let duration = String(format: String(localized: "meeting.settings.duration.format"), meeting.durationMinutes)
        let cities = meeting.participantNames.joined(separator: String(localized: "meeting.slots.constraints.join"))
        return "\(duration) · \(cities)"
    }

    private func timeText(_ date: Date, timezoneId: String) -> String {
        if use24Hour {
            return timezoneService.getLocalTime24(timezoneId: timezoneId, date: date) ?? ""
        }
        return timezoneService.getLocalTime12(timezoneId: timezoneId, date: date) ?? ""
    }

    private func dateText(_ date: Date, timezoneId: String) -> String {
        var style = Date.FormatStyle.dateTime.month(.defaultDigits).day().weekday(.abbreviated)
        style.timeZone = TimeZone(identifier: timezoneId) ?? .current
        return date.formatted(style)
    }

}

#Preview {
    MeetingListView()
        .environmentObject(AppEnvironment())
}
