import SwiftUI

/// 所有城市提醒列表：展示已添加的提醒，支持滑动删除。
struct ReminderListView: View {
    @StateObject private var viewModel = ReminderListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    private var use24Hour: Bool {
        appEnvironment.settings.use24Hour
    }

    /// 按城市名分组的提醒
    private var groupedReminders: [(cityName: String, reminders: [CityReminderGroup])] {
        let grouped = Dictionary(grouping: viewModel.reminders, by: { $0.cityName })
        return grouped
            .sorted { $0.key < $1.key }
            .map { (cityName: $0.key, reminders: $0.value) }
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
                    Section {
                    } header: {
                        Text(String(localized: "reminder.list.swipe.hint"))
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .textCase(nil)
                    }

                    ForEach(groupedReminders, id: \.cityName) { group in
                        Section {
                            ForEach(group.reminders) { reminder in
                                reminderRow(reminder)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteReminder(reminder)
                                            }
                                        } label: {
                                            Label(String(localized: "city.reminder.remove"), systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text(group.cityName)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.loadReminders()
        }
    }

    private func reminderRow(_ reminder: CityReminderGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.title3)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(formatTime(reminder.hour, reminder.minute))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    if reminder.weekdaysOnly {
                        Text(String(localized: "city.reminder.weekdays.only"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text("(")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(reminder.cityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let crossDay = crossDayLabel(for: reminder) {
                        Text(crossDay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatTime(reminder.targetHour, reminder.targetMinute))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text(")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// 计算提醒的目标时间相对本地时间的跨天标签（昨日/明日）
    private func crossDayLabel(for reminder: CityReminderGroup) -> String? {
        let localTzId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
        guard let targetTZ = TimeZone(identifier: reminder.targetTimezoneId),
              let localTZ = TimeZone(identifier: localTzId) else {
            return nil
        }

        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = targetTZ
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = localTZ

        let now = Date()
        let targetDayStart = targetCal.startOfDay(for: now)
        guard let targetDate = targetCal.date(byAdding: .hour, value: reminder.targetHour, to: targetDayStart) else {
            return nil
        }

        let components: Set<Calendar.Component> = [.year, .month, .day]
        let targetComps = targetCal.dateComponents(components, from: targetDate)
        let localComps = localCal.dateComponents(components, from: targetDate)

        guard let tY = targetComps.year, let tM = targetComps.month, let tD = targetComps.day,
              let lY = localComps.year, let lM = localComps.month, let lD = localComps.day else {
            return nil
        }

        if tY < lY || (tY == lY && tM < lM) || (tY == lY && tM == lM && tD < lD) {
            return String(localized: "clock.yesterday")
        }
        if tY > lY || (tY == lY && tM > lM) || (tY == lY && tM == lM && tD > lD) {
            return String(localized: "clock.tomorrow")
        }
        return nil
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
}