import SwiftUI

// MARK: - TimelineBar（详情页 48 个半小时色条）

struct TimelineBar: View {
    let hourlyHighlight: [Bool]
    let highlightColor: Color
    let nowHour: Double?

    var body: some View {
        VStack(spacing: 3) {
            Canvas { context, size in
                let segmentCount = max(hourlyHighlight.count, 1)
                let segW = size.width / CGFloat(segmentCount)
                let h = size.height
                for segment in 0..<segmentCount {
                    let x = CGFloat(segment) * segW
                    let rect = CGRect(x: x, y: 0, width: max(segW - 1, 1), height: h)
                    let color: Color = hourlyHighlight[segment] ? highlightColor : Color(.systemGray5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
                if let now = nowHour {
                    let nowX = CGFloat(now) / 24 * size.width
                    let marker = CGRect(x: nowX - 1, y: -2, width: 2, height: h + 4)
                    context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(.red))
                }
            }
            .frame(height: 14)

            HStack {
                Text("0").font(.system(size: 9))
                Spacer()
                Text("6").font(.system(size: 9))
                Spacer()
                Text("12").font(.system(size: 9))
                Spacer()
                Text("18").font(.system(size: 9))
                Spacer()
                Text("24").font(.system(size: 9))
            }
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - CityDetailView

private struct PendingReminder {
    let localMinuteOfDay: Int
    let targetMinuteOfDay: Int
}

struct CityDetailView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CityDetailViewModel
    @State private var processingReminderSlots: Set<Int> = []
    @State private var pendingReminder: PendingReminder?
    @State private var reminderToastMessage: String?

    init(city: CityModel) {
        _viewModel = StateObject(wrappedValue: CityDetailViewModel(city: city))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                workHoursCard
                overlapCard
                reminderCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(CityDisplay.primaryName(cityName: viewModel.city.cityName, cityEn: viewModel.city.cityEn))
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
            viewModel.use24Hour = appEnvironment.settings.use24Hour
            viewModel.localTimezoneId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
            viewModel.localCityNameOverride = appEnvironment.settings.currentCityName
            viewModel.localCityEnOverride = appEnvironment.settings.currentCityEn
            Task {
                await viewModel.loadReminders()
            }
        }
        .onChange(of: appEnvironment.settings.currentCityTimezoneId) { _, _ in
            viewModel.localTimezoneId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
            viewModel.localCityNameOverride = appEnvironment.settings.currentCityName
            viewModel.localCityEnOverride = appEnvironment.settings.currentCityEn
        }
        .onReceive(appEnvironment.$currentDate) { newValue in
            viewModel.currentDate = newValue
        }
        .onDisappear {
            viewModel.saveWorkHours()
            appEnvironment.citiesRevision += 1
        }
        .confirmationDialog(
            String(localized: "city.reminder.weekdays.prompt"),
            isPresented: Binding(
                get: { pendingReminder != nil },
                set: { if !$0 { pendingReminder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "city.reminder.everyday")) {
                addPendingReminder(weekdayPolicy: .everyDay)
            }
            Button(String(localized: "city.reminder.weekdays.both")) {
                addPendingReminder(weekdayPolicy: .bothCities)
            }
            Button(
                String(
                    format: String(localized: "city.reminder.weekdays.single"),
                    CityDisplay.primaryName(cityName: viewModel.localCityName, cityEn: viewModel.localCityEn)
                )
            ) {
                addPendingReminder(weekdayPolicy: .currentCity)
            }
            Button(
                String(
                    format: String(localized: "city.reminder.weekdays.single"),
                    CityDisplay.primaryName(cityName: viewModel.city.cityName, cityEn: viewModel.city.cityEn)
                )
            ) {
                addPendingReminder(weekdayPolicy: .targetCity)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingReminder = nil
            }
        }
        .toast(message: $reminderToastMessage)
    }

    // MARK: - Work Hours（本地 + 目标城市合并卡片）

    private var workHoursCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader(
                    title: "detail.rules.title",
                    subtitle: "detail.rules.hint"
                )
                dashedDivider()

                cityWorkHoursSection(
                    cityName: viewModel.localCityName,
                    cityEn: viewModel.localCityEn,
                    dstStatus: viewModel.localDSTStatus,
                    countryCode: viewModel.localCountryCode,
                    timezoneId: viewModel.localTimezoneId,
                    timeDifference: "0h",
                    timeDifferenceColor: .secondary,
                    timeText: viewModel.localTime,
                    crossDay: nil,
                    hourlyHighlight: viewModel.localHalfHourlyWorking,
                    highlightColor: .accentColor,
                    cityIcon: "location.fill",
                    nowHour: viewModel.localNowHour,
                    workStartMinutes: $viewModel.localWorkStartMinutes,
                    workEndMinutes: $viewModel.localWorkEndMinutes,
                    showLocalBadge: true
                )

                cityWorkHoursSection(
                    cityName: viewModel.city.cityName,
                    cityEn: viewModel.city.cityEn,
                    dstStatus: viewModel.targetDSTStatus,
                    countryCode: viewModel.targetCountryCode,
                    timezoneId: viewModel.city.timezoneId,
                    timeDifference: viewModel.timeDifference,
                    timeDifferenceColor: timeDifferenceColor,
                    timeText: viewModel.cityTime,
                    crossDay: viewModel.targetCrossDay,
                    hourlyHighlight: viewModel.targetHalfHourlyWorking,
                    highlightColor: .blue,
                    cityIcon: "building.2",
                    nowHour: viewModel.targetNowHour,
                    workStartMinutes: $viewModel.targetWorkStartMinutes,
                    workEndMinutes: $viewModel.targetWorkEndMinutes
                )
                .padding(.top, 16)
            }
        }
    }

    private var timeDifferenceColor: Color {
        let offset = viewModel.timeDifference
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }

    private func cityWorkHoursSection(
        cityName: String,
        cityEn: String,
        dstStatus: String?,
        countryCode: String,
        timezoneId: String,
        timeDifference: String,
        timeDifferenceColor: Color,
        timeText: String,
        crossDay: String?,
        hourlyHighlight: [Bool],
        highlightColor: Color,
        cityIcon: String,
        nowHour: Double?,
        workStartMinutes: Binding<Int>,
        workEndMinutes: Binding<Int>,
        showLocalBadge: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        moduleIcon(cityIcon, size: 22)
                        Text(CityDisplay.primaryName(cityName: cityName, cityEn: cityEn))
                            .font(.body)
                            .fontWeight(.semibold)
                        if let secondary = CityDisplay.secondaryName(cityName: cityName, cityEn: cityEn) {
                        Text(secondary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        if showLocalBadge {
                            Text(String(localized: "meeting.local.badge"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                        dstBadge(dstStatus)
                    }
                    cityMetaRow(
                        countryCode: countryCode,
                        timezoneId: timezoneId,
                        timeDifference: timeDifference,
                        timeDifferenceColor: timeDifferenceColor
                    )
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(alignment: .center, spacing: 4) {
                        if let crossDay {
                            CrossDayBadge(label: crossDay)
                        }
                        Text(timeText)
                            .font(.body)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(String(localized: "detail.current.time"))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            TimelineBar(
                hourlyHighlight: hourlyHighlight,
                highlightColor: highlightColor,
                nowHour: nowHour
            )
            workHoursSteppers(start: workStartMinutes, end: workEndMinutes)
        }
    }

    // MARK: - Overlap

    private var overlapCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader(
                    title: "detail.contactable.period",
                    subtitle: "detail.rules.2"
                ) {
                    HStack(spacing: 2) {
                        Image(systemName: viewModel.overlap.isCurrentlyOverlapping ? "phone.fill" : "phone")
                        Text(viewModel.overlapStatusText)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(viewModel.overlap.isCurrentlyOverlapping ? .green : .secondary)
                    .lineLimit(1)
                }
                dashedDivider()
                TimelineBar(
                    hourlyHighlight: viewModel.overlap.halfHourlyOverlap,
                    highlightColor: .green,
                    nowHour: viewModel.localNowHour
                )
                Text(viewModel.overlapSummary)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(viewModel.overlap.isCurrentlyOverlapping ? .green : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(viewModel.overlap.isCurrentlyOverlapping ? Color.green.opacity(0.2) : Color.indigo.opacity(0.2))
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - City Reminder

    private var reminderCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader(
                    title: "city.reminder.title",
                    subtitle: "city.reminder.hint"
                )
                dashedDivider()

                let contactableSlots = viewModel.contactableSlots
                if !contactableSlots.isEmpty {
                    ForEach(contactableSlots) { slot in
                        ReminderRow(
                            targetMinuteOfDay: slot.targetMinuteOfDay,
                            localMinuteOfDay: slot.localMinuteOfDay,
                            cityName: CityDisplay.primaryName(cityName: viewModel.city.cityName, cityEn: viewModel.city.cityEn),
                            dayLabel: viewModel.targetDayLabel(for: slot.date),
                            existing: viewModel.reminder(atLocalMinute: slot.localMinuteOfDay),
                            isProcessing: processingReminderSlots.contains(slot.localMinuteOfDay),
                            onToggle: { existing in
                                Task {
                                    await toggleReminder(
                                        existing,
                                        localMinuteOfDay: slot.localMinuteOfDay,
                                        targetMinuteOfDay: slot.targetMinuteOfDay
                                    )
                                }
                            }
                        )
                        .equatable()
                    }

                } else {
                    Text(String(localized: "city.reminder.empty"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                let orphaned = viewModel.orphanedReminders
                if !orphaned.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(String(localized: "city.reminder.outdated"))
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        ForEach(orphaned) { reminder in
                            OrphanedReminderRow(
                                reminder: reminder,
                                cityName: CityDisplay.primaryName(cityName: viewModel.city.cityName, cityEn: viewModel.city.cityEn),
                                isProcessing: processingReminderSlots.contains(
                                    reminder.hour * MinuteTime.minutesPerHour + reminder.minute
                                ),
                                onRemove: {
                                    Task {
                                        let slotID = reminder.hour * MinuteTime.minutesPerHour + reminder.minute
                                        processingReminderSlots.insert(slotID)
                                        defer { processingReminderSlots.remove(slotID) }
                                        await viewModel.removeReminder(reminder)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, 4)
                }

                if let status = viewModel.reminderStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(viewModel.reminderStatusIsError ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func toggleReminder(
        _ existing: CityReminderGroup?,
        localMinuteOfDay: Int,
        targetMinuteOfDay: Int
    ) async {
        if let existing {
            processingReminderSlots.insert(localMinuteOfDay)
            defer { processingReminderSlots.remove(localMinuteOfDay) }
            await viewModel.removeReminder(existing)
        } else {
            pendingReminder = PendingReminder(
                localMinuteOfDay: localMinuteOfDay,
                targetMinuteOfDay: targetMinuteOfDay
            )
        }
    }

    private func addPendingReminder(weekdayPolicy: CityReminderWeekdayPolicy) {
        guard let pendingReminder else { return }
        self.pendingReminder = nil
        Task {
            processingReminderSlots.insert(pendingReminder.localMinuteOfDay)
            defer { processingReminderSlots.remove(pendingReminder.localMinuteOfDay) }
            let isAdded = await viewModel.addContactableReminder(
                localMinuteOfDay: pendingReminder.localMinuteOfDay,
                targetMinuteOfDay: pendingReminder.targetMinuteOfDay,
                weekdayPolicy: weekdayPolicy
            )
            if isAdded {
                reminderToastMessage = String(localized: "city.reminder.added.success")
            }
        }
    }

    // MARK: - Components

    private func cardHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                accessory()
            }
        }
    }

    private func moduleIcon(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: size, height: size)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }

    private func dashedDivider() -> some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
            }
            .stroke(
                Color(.separator).opacity(0.55),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }
        .frame(height: 1)
    }

    /// 城市元信息行：国旗 国家名 · UTC · 时差（与时钟列表卡片一致）
    private func cityMetaRow(
        countryCode: String,
        timezoneId: String,
        timeDifference: String,
        timeDifferenceColor: Color
    ) -> some View {
        HStack(spacing: 6) {
            if !countryCode.isEmpty {
                Text(flagEmoji(for: countryCode))
                    .font(.system(size: 13))
                Text(appCountryName(for: countryCode))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("·")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(utcText(for: timezoneId))
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
            Text("·")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(localized: "clock.time.difference"))
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
            Text(timeDifference)
                .font(.footnote.weight(.bold))
                .foregroundColor(timeDifferenceColor)
                .monospacedDigit()
        }
    }

    /// 夏令时胶囊标签
    @ViewBuilder
    private func dstBadge(_ status: String?) -> some View {
        if let status {
            Text(status)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(3)
        }
    }

    private func workHoursSteppers(start: Binding<Int>, end: Binding<Int>) -> some View {
        let validatedStart = Binding<Int>(
            get: { start.wrappedValue },
            set: { newValue in
                start.wrappedValue = newValue
                if end.wrappedValue <= newValue {
                    end.wrappedValue = min(
                        MinuteTime.minutesPerDay,
                        newValue + MinuteTime.stepMinutes
                    )
                }
            }
        )
        let validatedEnd = Binding<Int>(
            get: { end.wrappedValue },
            set: { newValue in
                if newValue <= start.wrappedValue {
                    end.wrappedValue = min(
                        MinuteTime.minutesPerDay,
                        start.wrappedValue + MinuteTime.stepMinutes
                    )
                } else {
                    end.wrappedValue = newValue
                }
            }
        )

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "detail.work.start"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(
                    value: validatedStart,
                    in: 0...(MinuteTime.minutesPerDay - MinuteTime.stepMinutes),
                    step: MinuteTime.stepMinutes
                ) {
                    Text(MinuteTime.text(validatedStart.wrappedValue))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(localized: "detail.work.end"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(
                    value: validatedEnd,
                    in: MinuteTime.stepMinutes...MinuteTime.minutesPerDay,
                    step: MinuteTime.stepMinutes
                ) {
                    Text(MinuteTime.text(validatedEnd.wrappedValue))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct ReminderRow: View, Equatable {
    let targetMinuteOfDay: Int
    let localMinuteOfDay: Int
    let cityName: String
    let dayLabel: String?
    let existing: CityReminderGroup?
    let isProcessing: Bool
    let onToggle: (CityReminderGroup?) -> Void

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.targetMinuteOfDay == rhs.targetMinuteOfDay
            && lhs.localMinuteOfDay == rhs.localMinuteOfDay
            && lhs.cityName == rhs.cityName
            && lhs.dayLabel == rhs.dayLabel
            && lhs.existing == rhs.existing
            && lhs.isProcessing == rhs.isProcessing
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text(MinuteTime.text(localMinuteOfDay))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Text("(")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(cityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let dayLabel {
                        Text(dayLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(MinuteTime.text(targetMinuteOfDay))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text(")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            if existing == nil {
                Button {
                    onToggle(existing)
                } label: {
                    Text(String(localized: "city.reminder.add"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            } else {
                Button {
                    onToggle(existing)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(existing == nil
            ? String(localized: "city.reminder.add")
            : String(localized: "city.reminder.cancel")
        )
    }
}

// MARK: - Orphaned Reminder Row

private struct OrphanedReminderRow: View {
    let reminder: CityReminderGroup
    let cityName: String
    let isProcessing: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text(
                    MinuteTime.text(
                        reminder.hour * MinuteTime.minutesPerHour + reminder.minute
                    )
                )
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                HStack(spacing: 3) {
                    Text("(")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(cityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(
                        MinuteTime.text(
                            reminder.targetHour * MinuteTime.minutesPerHour + reminder.targetMinute
                        )
                    )
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text(")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(String(localized: "city.reminder.remove.outdated"))
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
