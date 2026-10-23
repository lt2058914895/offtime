import SwiftUI
import Combine

private let reminderCardCornerRadius: CGFloat = 18

/// 所有城市提醒列表：展示已添加的提醒，支持滑动删除。
struct ReminderListView: View {
    @StateObject private var viewModel = ReminderListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var reminderToDelete: CityReminderGroup?
    @State private var now = Date()

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum ReminderDisplayStatus {
        case pending
        case dueSoon
        case remindedToday
        case notToday

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
            }
        }
    }

    private var use24Hour: Bool {
        appEnvironment.settings.use24Hour
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
                    Text(String(localized: "reminder.list.swipe.hint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    ForEach(viewModel.reminders) { reminder in
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
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            now = Date()
        }
        .onReceive(refreshTimer) { _ in
            now = Date()
        }
        .task {
            now = Date()
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
        let targetTimezone = TimeZone(identifier: reminder.targetTimezoneId) ?? .current
        let nextDate = CityReminderScheduler.nextOccurrence(
            after: now,
            timezoneId: reminder.timezoneId,
            hour: reminder.hour,
            minute: reminder.minute,
            weekdaysOnly: reminder.weekdaysOnly
        ) ?? Date()

        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.timeZone = targetTimezone
        dateFormatter.dateFormat = "yyyy/MM/dd EEE"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = targetTimezone
        let hour = calendar.component(.hour, from: nextDate)
        let minute = calendar.component(.minute, from: nextDate)

        return (dateFormatter.string(from: nextDate), formatTime(hour, minute))
    }

    private func formatTime(_ hour: Int, _ minute: Int) -> String {
        if use24Hour {
            return String(format: "%02d:%02d", hour, minute)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
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

// MARK: - 城市元信息辅助

/// 国家码 → 国旗 Emoji；非法/空返回 🌐 占位
private func flagEmoji(for countryCode: String) -> String {
    let upper = countryCode.uppercased()
    guard upper.count == 2, upper.allSatisfy({ $0.isASCII && $0.isLetter }) else {
        return "🌐"
    }
    let base: UInt32 = 127397
    return upper.unicodeScalars
        .compactMap { UnicodeScalar(base + $0.value) }
        .reduce(into: "") { result, scalar in
            result.unicodeScalars.append(scalar)
        }
}

/// 当前 App 语言下的国家名
private func appCountryName(for countryCode: String) -> String {
    guard countryCode.count == 2 else { return "" }
    let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
    let locale: Locale
    switch language {
    case "en": locale = Locale(identifier: "en_US")
    default: locale = Locale(identifier: "zh_CN")
    }
    return locale.localizedString(forRegionCode: countryCode) ?? ""
}

/// 时区 ID → UTC 偏移文案，如 UTC+8
private func utcText(for timezoneId: String) -> String {
    guard let timeZone = TimeZone(identifier: timezoneId) else { return "" }
    let seconds = timeZone.secondsFromGMT()
    let hours = seconds / 3600
    let minutes = abs(seconds % 3600) / 60
    if minutes == 0 {
        return String(format: "UTC%+d", hours)
    }
    return String(format: "UTC%+d:%02d", hours, minutes)
}
