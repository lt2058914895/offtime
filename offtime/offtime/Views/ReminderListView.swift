import SwiftUI

private let reminderCardCornerRadius: CGFloat = 18

/// 所有城市提醒列表：展示已添加的提醒，支持滑动删除。
struct ReminderListView: View {
    @StateObject private var viewModel = ReminderListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderToDelete: CityReminderGroup?
    @AppStorage("settings_reminderSortMode") private var sortMode: ReminderSortMode = .time

    private enum ReminderSortMode: String, CaseIterable, Identifiable {
        case time
        case city

        var id: Self { self }

        var title: String {
            switch self {
            case .time:
                return String(localized: "reminder.sort.time")
            case .city:
                return String(localized: "reminder.sort.city")
            }
        }
    }

    private enum ReminderDisplayStatus {
        case pending
        case dueSoon
        case remindedToday
        case notToday
        case notificationsOff

        var title: String {
            switch self {
            case .pending:
                return String(localized: "reminder.status.pending")
            case .dueSoon:
                return String(localized: "reminder.status.dueSoon")
            case .remindedToday:
                return String(localized: "reminder.status.reminded")
            case .notToday:
                return String(localized: "reminder.status.notToday")
            case .notificationsOff:
                return String(localized: "reminder.status.notificationsOff")
            }
        }

        var icon: String {
            switch self {
            case .pending:
                return "clock.fill"
            case .dueSoon:
                return "alarm.fill"
            case .remindedToday:
                return "checkmark.circle.fill"
            case .notToday:
                return "calendar"
            case .notificationsOff:
                return "bell.slash.fill"
            }
        }

        var tint: Color {
            switch self {
            case .pending:
                return .green
            case .dueSoon:
                return .orange
            case .remindedToday, .notToday:
                return .secondary
            case .notificationsOff:
                return .orange
            }
        }
    }

    private var use24Hour: Bool {
        appEnvironment.settings.use24Hour
    }

    private var now: Date {
        appEnvironment.currentDate
    }

    var body: some View {
        Group {
            if viewModel.reminders.isEmpty {
                ContentUnavailableView(
                    String(localized: "reminder.list.empty.title"),
                    systemImage: "bell.slash",
                    description: Text(String(localized: "reminder.list.empty"))
                )
            } else {
                List {
                    if !viewModel.isNotificationDeliveryAvailable {
                        notificationDisabledBanner
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 2, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    Text(String(localized: "reminder.list.swipe.hint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if sortMode == .time {
                        ForEach(timeSortedReminders) { reminder in
                            reminderListRow(reminder)
                        }
                    } else {
                        ForEach(citySections) { section in
                            Section {
                                ForEach(section.reminders) { reminder in
                                    reminderListRow(reminder)
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Text(CountryDisplay.flagEmoji(for: section.countryCode))
                                        .font(.title3)

                                    HStack(spacing: 4) {
                                        Text(section.title)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        if let secondaryTitle = section.secondaryTitle {
                                            Text(secondaryTitle)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.top, 4)
                                .textCase(nil)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle(String(localized: "reminder.list.title"))
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
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            updateMinuteClock()
        }
        .onDisappear {
            appEnvironment.stopMinuteClock()
        }
        .onChange(of: scenePhase) { _, phase in
            updateMinuteClock()
            if phase == .active {
                Task {
                    await viewModel.refreshNotificationAvailability()
                }
            }
        }
        .task {
            await viewModel.loadReminders()
        }
        .confirmationDialog(
            String(localized: "reminder.list.delete.confirm.title"),
            isPresented: Binding(
                get: { reminderToDelete != nil },
                set: { if !$0 { reminderToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: reminderToDelete
        ) { reminder in
            Button(String(localized: "common.delete"), role: .destructive) {
                reminderToDelete = nil
                Task {
                    await viewModel.deleteReminder(reminder)
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                reminderToDelete = nil
            }
        } message: { reminder in
            Text(deleteConfirmationMessage(for: reminder))
        }
    }

    private func deleteConfirmationMessage(for reminder: CityReminderGroup) -> String {
        let city = viewModel.city(for: reminder.cityID)
        let cityName = city.map {
            CityDisplay.primaryName(cityName: $0.cityName, cityEn: $0.cityEn)
        } ?? reminder.cityName
        let triggerTime = formatTime(reminder.hour, reminder.minute)
        let targetTime = formatTime(reminder.targetHour, reminder.targetMinute)
        return "\(triggerTime) (\(cityName) \(targetTime))"
    }

    private func reminderListRow(_ reminder: CityReminderGroup) -> some View {
        reminderRow(reminder)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    reminderToDelete = reminder
                } label: {
                    Label(String(localized: "city.reminder.remove"), systemImage: "trash")
                }
            }
    }

    private var notificationDisabledBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "reminder.list.notifications.disabled.title"))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)

                Text(String(localized: "reminder.list.notifications.disabled.message"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var timeSortedReminders: [CityReminderGroup] {
        viewModel.reminders.sorted(by: timeSort)
    }

    private var citySections: [ReminderCitySection] {
        Dictionary(grouping: viewModel.reminders, by: \.cityID)
            .map { cityID, reminders in
                let sorted = reminders.sorted(by: timeSort)
                let names = cityDisplayNames(for: sorted[0])
                let countryCode = viewModel.city(for: cityID).map {
                    viewModel.countryCode(for: $0)
                } ?? ""
                return ReminderCitySection(
                    id: cityID,
                    countryCode: countryCode,
                    title: names.primary,
                    secondaryTitle: names.secondary,
                    reminders: sorted
                )
            }
            .sorted { lhs, rhs in
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private struct ReminderCitySection: Identifiable {
        let id: UUID
        let countryCode: String
        let title: String
        let secondaryTitle: String?
        let reminders: [CityReminderGroup]
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ReminderSortMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sortMode = mode
                    }
                } label: {
                    if sortMode == mode {
                        Text(mode.title)
                            + Text(verbatim: "  ")
                            + Text(Image(systemName: "checkmark"))
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sortMode.title)
                    .font(.subheadline)
                    .foregroundColor(.blue)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.blue)
            }
        }
        .accessibilityLabel(String(localized: "reminder.sort.label"))
    }

    private func timeSort(_ lhs: CityReminderGroup, _ rhs: CityReminderGroup) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }
        if lhs.minute != rhs.minute {
            return lhs.minute < rhs.minute
        }
        let lhsCity = cityDisplayName(for: lhs)
        let rhsCity = cityDisplayName(for: rhs)
        if lhsCity != rhsCity {
            return lhsCity.localizedStandardCompare(rhsCity) == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func cityDisplayName(for reminder: CityReminderGroup) -> String {
        cityDisplayNames(for: reminder).primary
    }

    private func cityDisplayNames(for reminder: CityReminderGroup) -> (primary: String, secondary: String?) {
        guard let city = viewModel.city(for: reminder.cityID) else {
            return (reminder.cityName, nil)
        }
        return (
            CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn),
            CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn)
        )
    }

    private func reminderRow(_ reminder: CityReminderGroup) -> some View {
        let city = viewModel.city(for: reminder.cityID)
        let displayName = city.map { CityDisplay.primaryName(cityName: $0.cityName, cityEn: $0.cityEn) } ?? reminder.cityName
        let timeDiff = timeDifference(for: reminder)
        let status = displayStatus(for: reminder, now: now)
        let targetDateTime = targetDateTimeText(for: reminder, now: now)
        return ZStack(alignment: .topLeading) {
            if reminder.weekdaysOnly {
                weekdayOnlyBadge
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatTime(reminder.hour, reminder.minute))
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.secondary)
                        Text("·")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(targetDateTime.time)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(localized: "clock.time.difference"))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                        Text(timeDiff)
                            .font(.footnote.weight(.bold))
                            .foregroundColor(timeDifferenceColor(timeDiff))
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(String(localized: "reminder.list.next") + ":")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(targetDateTime.date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, reminder.weekdaysOnly ? 14 : 0)

                Spacer(minLength: 8)

                statusBadge(status)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: reminderCardCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: reminderCardCornerRadius, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: reminderCardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var weekdayOnlyBadge: some View {
        Text(String(localized: "city.reminder.weekdays.only"))
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.leading, 14)
            .padding(.trailing, 11)
            .padding(.vertical, 4)
            .background(
                ReminderWeekdayBadgeShape()
                    .fill(Color.orange)
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private func statusBadge(_ status: ReminderDisplayStatus) -> some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
                .font(.caption2.weight(.semibold))

            Text(status.title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(status.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(status.tint.opacity(0.12)))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func displayStatus(for reminder: CityReminderGroup, now: Date) -> ReminderDisplayStatus {
        guard viewModel.isNotificationDeliveryAvailable else {
            return .notificationsOff
        }
        guard let timezone = TimeZone(identifier: reminder.timezoneId) else {
            return .pending
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        if reminder.weekdaysOnly {
            let weekday = calendar.component(.weekday, from: now)
            if weekday == 1 || weekday == 7 {
                return .notToday
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = reminder.hour
        components.minute = reminder.minute
        components.second = 0

        guard let todayOccurrence = calendar.date(from: components) else {
            return .pending
        }

        if now >= todayOccurrence {
            return .remindedToday
        }
        if todayOccurrence.timeIntervalSince(now) <= 30 * 60 {
            return .dueSoon
        }
        return .pending
    }

    private func targetDateTimeText(
        for reminder: CityReminderGroup,
        now: Date
    ) -> (date: String, time: String) {
        let nextDate = CityReminderScheduler.nextOccurrence(
            after: now,
            timezoneId: reminder.timezoneId,
            hour: reminder.hour,
            minute: reminder.minute,
            weekdaysOnly: reminder.weekdaysOnly
        ) ?? Date()

        let timezoneService = TimezoneService.shared
        let date = timezoneService.getLocalDateWithWeekday(
            timezoneId: reminder.targetTimezoneId,
            date: nextDate
        ) ?? ""
        let time = use24Hour
            ? timezoneService.getLocalTime24(timezoneId: reminder.targetTimezoneId, date: nextDate)
            : timezoneService.getLocalTime12(timezoneId: reminder.targetTimezoneId, date: nextDate)
        return (date, time ?? formatTime(reminder.targetHour, reminder.targetMinute))
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        TimezoneService.shared.getTime(hour: hour, minute: minute, use24Hour: use24Hour)
    }

    private func updateMinuteClock() {
        if scenePhase == .active {
            appEnvironment.startMinuteClock()
        } else {
            appEnvironment.stopMinuteClock()
        }
    }

    private func timeDifference(for reminder: CityReminderGroup) -> String {
        let city = viewModel.city(for: reminder.cityID)
        let targetTimezoneId = city?.timezoneId ?? reminder.targetTimezoneId
        let localTimezoneId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
        return viewModel.timeDifference(for: targetTimezoneId, localTimezoneId: localTimezoneId)
    }

    private func timeDifferenceColor(_ offset: String) -> Color {
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }

}

private struct ReminderWeekdayBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cornerRadius = reminderCardCornerRadius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
