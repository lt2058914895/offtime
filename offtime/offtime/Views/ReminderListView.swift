import SwiftUI

private let reminderCardCornerRadius: CGFloat = 18

/// 所有城市提醒列表：展示已添加的提醒，支持滑动删除。
struct ReminderListView: View {
    @StateObject private var viewModel = ReminderListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderToDelete: CityReminderGroup?
    @State private var reminderToEdit: CityReminderGroup?
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

    private enum ReminderDisplayStatus: Equatable {
        case paused
        case pending
        case dueSoon
        case remindedToday
        case notToday
        case notificationsOff

        var title: String {
            switch self {
            case .paused:
                return String(localized: "reminder.status.paused")
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
            case .paused:
                return "pause.circle.fill"
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
            case .paused:
                return .secondary
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

                    Text(String(localized: "reminder.list.hint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if sortMode == .time {
                        ForEach(activeTimeSortedReminders) { reminder in
                            reminderListRow(reminder)
                        }

                        if !pausedReminders.isEmpty {
                            Section {
                                ForEach(pausedReminders) { reminder in
                                    reminderListRow(reminder)
                                }
                            } header: {
                                pausedSectionHeader
                            }
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
        .alert(
            String(localized: "reminder.action.updateFailed.title"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button(String(localized: "common.ok")) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "city.reminder.weekdays.prompt"),
            isPresented: Binding(
                get: { reminderToEdit != nil },
                set: { if !$0 { reminderToEdit = nil } }
            ),
            titleVisibility: .visible,
            presenting: reminderToEdit
        ) { reminder in
            let activeReminder = viewModel.reminders.first { $0.id == reminder.id } ?? reminder
            let isLocalReminder = activeReminder.timezoneId == activeReminder.targetTimezoneId

            if isLocalReminder {
                Button(String(localized: "city.reminder.everyday")) {
                    reminderToEdit = nil
                    updateReminderPolicy(activeReminder, to: .everyDay)
                }

                Button(String(localized: "city.reminder.weekdays.badge.both")) {
                    reminderToEdit = nil
                    let policy = activeReminder.weekdayPolicy == .everyDay
                        ? .bothCities
                        : activeReminder.weekdayPolicy
                    updateReminderPolicy(activeReminder, to: policy)
                }
            } else {
                ForEach(CityReminderWeekdayPolicy.allCases) { policy in
                    Button(weekdayPolicyText(policy, for: activeReminder)) {
                        reminderToEdit = nil
                        updateReminderPolicy(activeReminder, to: policy)
                    }
                }
            }

            Button(String(localized: "common.cancel"), role: .cancel) {
                reminderToEdit = nil
            }
        }
    }

    private func deleteConfirmationMessage(for reminder: CityReminderGroup) -> String {
        let cityName = cityDisplayName(for: reminder)
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
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    togglePause(for: reminder)
                } label: {
                    Label(
                        reminder.isPaused
                            ? String(localized: "reminder.action.resume")
                            : String(localized: "reminder.action.pause"),
                        systemImage: reminder.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .tint(reminder.isPaused ? .green : .orange)
            }
            .onLongPressGesture {
                reminderToEdit = reminder
            }
    }

    private func togglePause(for reminder: CityReminderGroup) {
        Task {
            await viewModel.setPaused(!reminder.isPaused, for: reminder)
        }
    }

    private func updateReminderPolicy(_ reminder: CityReminderGroup, to policy: CityReminderWeekdayPolicy) {
        Task {
            await viewModel.updateReminderPolicy(reminder, to: policy)
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

    private var activeTimeSortedReminders: [CityReminderGroup] {
        timeSortedReminders.filter { !$0.isPaused }
    }

    private var pausedReminders: [CityReminderGroup] {
        timeSortedReminders.filter(\.isPaused)
    }

    private var pausedSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle.fill")
                .font(.caption.weight(.semibold))

            Text(String(localized: "reminder.section.paused"))
                .font(.footnote.weight(.semibold))

            Spacer()

            Text("\(pausedReminders.count)")
                .font(.caption.monospacedDigit())
        }
        .foregroundColor(.secondary)
        .padding(.top, 8)
        .textCase(nil)
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
                let lhsHasActiveReminder = lhs.reminders.contains { !$0.isPaused }
                let rhsHasActiveReminder = rhs.reminders.contains { !$0.isPaused }
                if lhsHasActiveReminder != rhsHasActiveReminder {
                    return lhsHasActiveReminder
                }
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
        if lhs.isPaused != rhs.isPaused {
            return !lhs.isPaused
        }
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
            let matched = CityService.matchCity(
                cityName: reminder.cityName,
                timezoneId: reminder.targetTimezoneId
            )
            return (
                CityDisplay.primaryName(cityName: reminder.cityName, cityEn: matched.en),
                CityDisplay.secondaryName(cityName: reminder.cityName, cityEn: matched.en)
            )
        }
        return (
            CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn),
            CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn)
        )
    }

    private func reminderRow(_ reminder: CityReminderGroup) -> some View {
        let cityNames = cityDisplayNames(for: reminder)
        let timeDiff = timeDifference(for: reminder)
        let status = displayStatus(for: reminder, now: now)
        let timing = scheduleText(for: reminder, now: now)
        let isLocalReminder = reminder.timezoneId == reminder.targetTimezoneId
        let weekendDetail = status == .notToday
            ? weekendSkipDetail(for: reminder, now: now)
            : nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(weekdayPolicyText(for: reminder))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.4)

                Spacer(minLength: 8)

                Text(status.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(status.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(formatTime(reminder.hour, reminder.minute))
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLocalReminder {
                    Spacer(minLength: 8)
                } else {
                    timeBridge(timeDifference: timeDiff)
                        .frame(width: 54)

                    VStack(alignment: .trailing, spacing: 3) {
                        cityTitle(primary: cityNames.primary, secondary: nil)

                        Text(timing.targetTime)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    if reminder.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.caption2)

                        Text(String(localized: "reminder.status.paused.detail"))
                            .font(.caption2)
                    } else {
                        Text("\(String(localized: "reminder.list.next")):")
                            .font(.caption2)

                        Text(timing.triggerDate)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

                Spacer(minLength: 10)

                pauseResumeButton(for: reminder)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let weekendDetail {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption2)

                    Text(weekendDetail)
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(.secondary)
            }
        }
        .opacity(reminder.isPaused ? 0.3 : 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: reminderCardCornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: reminderCardCornerRadius, style: .continuous)
                .strokeBorder(
                    Color(uiColor: .separator).opacity(reminder.isPaused ? 0.3 : 0.18),
                    lineWidth: 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: reminderCardCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func cityTitle(primary: String, secondary: String?) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Text(primary)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundColor(.primary)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.4)
                .layoutPriority(1)

            if let secondary {
                Text(secondary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func timeBridge(timeDifference: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color(uiColor: .separator).opacity(0.55))
                    .frame(width: 15, height: 1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(timeDifference)
                .font(.caption2.weight(.bold))
                .foregroundColor(timeDifferenceColor(timeDifference))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityHidden(true)
    }

    private func weekdayPolicyText(for reminder: CityReminderGroup) -> String {
        weekdayPolicyText(reminder.weekdayPolicy, for: reminder)
    }

    private func weekdayPolicyText(
        _ policy: CityReminderWeekdayPolicy,
        for reminder: CityReminderGroup
    ) -> String {
        if reminder.timezoneId == reminder.targetTimezoneId,
           policy != .everyDay {
            return String(localized: "city.reminder.weekdays.badge.both")
        }

        switch policy {
        case .everyDay:
            return String(localized: "city.reminder.everyday")
        case .bothCities:
            return String(localized: "city.reminder.weekdays.badge.both")
        case .currentCity:
            return String(
                format: String(localized: "city.reminder.weekdays.single"),
                triggerCityDisplayName(for: reminder)
            )
        case .targetCity:
            return String(
                format: String(localized: "city.reminder.weekdays.single"),
                cityDisplayName(for: reminder)
            )
        }
    }

    private func displayStatus(for reminder: CityReminderGroup, now: Date) -> ReminderDisplayStatus {
        guard !reminder.isPaused else {
            return .paused
        }
        guard viewModel.isNotificationDeliveryAvailable else {
            return .notificationsOff
        }
        guard let timezone = TimeZone(identifier: reminder.timezoneId) else {
            return .pending
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = reminder.hour
        components.minute = reminder.minute
        components.second = 0

        guard let todayOccurrence = calendar.date(from: components) else {
            return .pending
        }

        if !CityReminderScheduler.isAllowedOccurrence(
               at: todayOccurrence,
               timezoneId: reminder.timezoneId,
               targetTimezoneId: reminder.targetTimezoneId,
               weekdayPolicy: reminder.weekdayPolicy
           ) {
            return .notToday
        }

        if now >= todayOccurrence {
            return .remindedToday
        }
        if todayOccurrence.timeIntervalSince(now) <= 30 * 60 {
            return .dueSoon
        }
        return .pending
    }

    private func pauseResumeButton(for reminder: CityReminderGroup) -> some View {
        let tint: Color = .secondary
        let iconTint = Color(uiColor: .tertiaryLabel)
        let title = reminder.isPaused
            ? String(localized: "reminder.action.resume")
            : String(localized: "reminder.action.pause")
        let icon = reminder.isPaused ? "play.fill" : "pause.fill"
        let isUpdating = viewModel.isPauseUpdating(reminder)
        let background = Color.secondary.opacity(0.08)

        return Button {
            togglePause(for: reminder)
        } label: {
            HStack(spacing: 4) {
                if isUpdating {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(iconTint)
                } else {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(iconTint)
                }

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isUpdating)
        .opacity(isUpdating ? 0.6 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(String(localized: "reminder.action.hint"))
    }

    private func weekendSkipDetail(for reminder: CityReminderGroup, now: Date) -> String? {
        guard reminder.weekdayPolicy.requiresWeekdayFiltering,
              let timezone = TimeZone(identifier: reminder.timezoneId) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = reminder.hour
        components.minute = reminder.minute
        components.second = 0

        guard let todayOccurrence = calendar.date(from: components),
              !CityReminderScheduler.isAllowedOccurrence(
                  at: todayOccurrence,
                  timezoneId: reminder.timezoneId,
                  targetTimezoneId: reminder.targetTimezoneId,
                  weekdayPolicy: reminder.weekdayPolicy
              ) else {
            return nil
        }

        var skippedCities: [String] = []
        if reminder.weekdayPolicy.includesCurrentCity,
           CityReminderScheduler.isWeekend(at: todayOccurrence, timezoneId: reminder.timezoneId) == true {
            let weekday = TimezoneService.shared.getLocalWeekday(
                timezoneId: reminder.timezoneId,
                date: todayOccurrence
            ) ?? ""
            skippedCities.append("\(triggerCityDisplayName(for: reminder)) \(weekday)")
        }
        if reminder.weekdayPolicy.includesTargetCity,
           CityReminderScheduler.isWeekend(at: todayOccurrence, timezoneId: reminder.targetTimezoneId) == true {
            let weekday = TimezoneService.shared.getLocalWeekday(
                timezoneId: reminder.targetTimezoneId,
                date: todayOccurrence
            ) ?? ""
            skippedCities.append("\(cityDisplayName(for: reminder)) \(weekday)")
        }
        guard !skippedCities.isEmpty else { return nil }

        return String(
            format: String(localized: "reminder.status.weekendSkip"),
            skippedCities.joined(separator: " / ")
        )
    }

    private func triggerCityDisplayName(for reminder: CityReminderGroup) -> String {
        if let triggerCityName = reminder.triggerCityName {
            let matched = CityService.matchCity(
                cityName: triggerCityName,
                timezoneId: reminder.timezoneId
            )
            return CityDisplay.primaryName(
                cityName: triggerCityName,
                cityEn: reminder.triggerCityEn ?? matched.en
            )
        }

        if appEnvironment.settings.currentCityTimezoneId == reminder.timezoneId,
           let currentCityName = appEnvironment.settings.currentCityName {
            let matched = CityService.matchCity(
                cityName: currentCityName,
                timezoneId: reminder.timezoneId
            )
            return CityDisplay.primaryName(
                cityName: currentCityName,
                cityEn: appEnvironment.settings.currentCityEn ?? matched.en
            )
        }

        let city = CityService.matchCity(for: reminder.timezoneId)
        return CityDisplay.primaryName(cityName: city.name, cityEn: city.en)
    }

    private func scheduleText(
        for reminder: CityReminderGroup,
        now: Date
    ) -> (triggerDate: String, targetTime: String, crossDay: String?) {
        guard let nextDate = CityReminderScheduler.nextOccurrence(
            after: now,
            timezoneId: reminder.timezoneId,
            hour: reminder.hour,
            minute: reminder.minute,
            targetTimezoneId: reminder.targetTimezoneId,
            weekdayPolicy: reminder.weekdayPolicy
        ) else {
            return (
                "--",
                formatTime(reminder.targetHour, reminder.targetMinute),
                nil
            )
        }

        let timezoneService = TimezoneService.shared
        let triggerDate = timezoneService.getLocalDateWithWeekday(
            timezoneId: reminder.timezoneId,
            date: nextDate
        ) ?? ""
        let targetTime = use24Hour
            ? timezoneService.getLocalTime24(timezoneId: reminder.targetTimezoneId, date: nextDate)
            : timezoneService.getLocalTime12(timezoneId: reminder.targetTimezoneId, date: nextDate)
        let crossDay = timezoneService.getTimeDifferenceBetween(
            sourceTimezoneId: reminder.timezoneId,
            targetTimezoneId: reminder.targetTimezoneId,
            date: nextDate
        ).crossDay
        return (
            triggerDate,
            targetTime ?? formatTime(reminder.targetHour, reminder.targetMinute),
            crossDay
        )
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
        viewModel.timeDifference(
            for: reminder.targetTimezoneId,
            localTimezoneId: reminder.timezoneId
        )
    }

    private func timeDifferenceColor(_ offset: String) -> Color {
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }

}
