import SwiftUI

// MARK: - TimelineBar（详情页 24 小时色条）

struct TimelineBar: View {
    let hourlyHighlight: [Bool]
    let highlightColor: Color
    let nowHour: Double?

    var body: some View {
        VStack(spacing: 3) {
            Canvas { context, size in
                let segW = size.width / 24
                let h = size.height
                for hour in 0..<24 {
                    let x = CGFloat(hour) * segW
                    let rect = CGRect(x: x, y: 0, width: max(segW - 1, 1), height: h)
                    let color: Color = hourlyHighlight[hour] ? highlightColor : Color(.systemGray5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
                if let now = nowHour {
                    let nowX = CGFloat(now) * segW
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

struct CityDetailView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CityDetailViewModel
    @State private var processingReminderTargetHours: Set<Int> = []

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
        .navigationTitle(viewModel.city.cityName)
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
            viewModel.use24Hour = appEnvironment.settings.use24Hour
            viewModel.localTimezoneId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
            Task {
                await viewModel.loadReminders()
            }
        }
        .onReceive(appEnvironment.$currentDate) { newValue in
            viewModel.currentDate = newValue
        }
        .onDisappear {
            viewModel.saveWorkHours()
            appEnvironment.citiesRevision += 1
        }
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
                    hourlyHighlight: viewModel.localHourlyWorking,
                    highlightColor: .accentColor,
                    cityIcon: "location.fill",
                    nowHour: viewModel.localNowHour,
                    workStart: $viewModel.localWorkStart,
                    workEnd: $viewModel.localWorkEnd
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
                    hourlyHighlight: viewModel.targetHourlyWorking,
                    highlightColor: .blue,
                    cityIcon: "building.2",
                    nowHour: viewModel.targetNowHour,
                    workStart: $viewModel.targetWorkStart,
                    workEnd: $viewModel.targetWorkEnd
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
        hourlyHighlight: [Bool],
        highlightColor: Color,
        cityIcon: String,
        nowHour: Double?,
        workStart: Binding<Int>,
        workEnd: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        moduleIcon(cityIcon, size: 22)
                        Text(cityName)
                            .font(.body)
                            .fontWeight(.semibold)
                        Text(cityEn)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    Text(timeText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
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
            workHoursSteppers(start: workStart, end: workEnd)
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
                    if viewModel.overlap.isCurrentlyOverlapping {
                        Text(String(localized: "detail.contactable.now"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
                dashedDivider()
                TimelineBar(
                    hourlyHighlight: viewModel.overlap.hourlyOverlap,
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
                    .background(viewModel.overlap.isCurrentlyOverlapping ? Color.green.opacity(0.12) : Color(.tertiarySystemFill))
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

                let contactableHours = viewModel.contactableTargetHours
                if !contactableHours.isEmpty {
                    ForEach(contactableHours, id: \.self) { targetHour in
                        let localHour = viewModel.localHour(forTargetHour: targetHour)
                        ReminderRow(
                            targetHour: targetHour,
                            localHour: localHour,
                            cityName: viewModel.city.cityName,
                            dayLabel: viewModel.targetDayLabel(forTargetHour: targetHour),
                            existing: viewModel.reminder(atHour: localHour, minute: 0),
                            isProcessing: processingReminderTargetHours.contains(targetHour),
                            onToggle: { existing in
                                Task {
                                    await toggleReminder(
                                        existing,
                                        localHour: localHour,
                                        targetHour: targetHour
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

                Toggle(
                    String(localized: "city.reminder.weekdays.only"),
                    isOn: $viewModel.reminderWeekdaysOnly
                )

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
        localHour: Int,
        targetHour: Int
    ) async {
        processingReminderTargetHours.insert(targetHour)
        defer { processingReminderTargetHours.remove(targetHour) }

        if let existing {
            await viewModel.removeReminder(existing)
        } else {
            await viewModel.addContactableReminder(
                localHour: localHour,
                targetHour: targetHour
            )
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

    /// 可联系时段钟点文案（24 小时制，与重叠摘要一致）
    private func contactTimeText(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
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
                .font(.caption2.weight(.medium))
                .foregroundColor(timeDifferenceColor)
                .monospacedDigit()
        }
    }

    /// 夏令时/冬令时胶囊标签（样式与时钟列表卡片一致）
    @ViewBuilder
    private func dstBadge(_ status: String?) -> some View {
        if let status {
            Text(status)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(status == String(localized: "clock.dst.summer") ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(status == String(localized: "clock.dst.summer") ? .orange : .blue)
                .cornerRadius(3)
        }
    }

    private func workHoursSteppers(start: Binding<Int>, end: Binding<Int>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "detail.work.start"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(value: start, in: 0...23) {
                    Text(String(format: "%02d:00", start.wrappedValue))
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(localized: "detail.work.end"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(value: end, in: 1...24) {
                    Text(String(format: "%02d:00", end.wrappedValue))
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
    let targetHour: Int
    let localHour: Int
    let cityName: String
    let dayLabel: String?
    let existing: CityReminderGroup?
    let isProcessing: Bool
    let onToggle: (CityReminderGroup?) -> Void

    static func == (lhs: ReminderRow, rhs: ReminderRow) -> Bool {
        lhs.targetHour == rhs.targetHour
            && lhs.localHour == rhs.localHour
            && lhs.cityName == rhs.cityName
            && lhs.dayLabel == rhs.dayLabel
            && lhs.existing == rhs.existing
            && lhs.isProcessing == rhs.isProcessing
    }

    var body: some View {
        Button {
            onToggle(existing)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Text(String(format: "%02d:00", localHour))
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
                        Text(String(format: "%02d:00", targetHour))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Text(")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if existing == nil {
                    Text(String(localized: "city.reminder.add"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(existing == nil
            ? String(localized: "city.reminder.add")
            : String(localized: "city.reminder.cancel")
        )
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
    case "ja": locale = Locale(identifier: "ja_JP")
    case "ko": locale = Locale(identifier: "ko_KR")
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
