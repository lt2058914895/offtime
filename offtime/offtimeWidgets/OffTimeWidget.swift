import Foundation
import SwiftUI
import WidgetKit
import AppIntents
import os

struct OffTimeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct OffTimeProvider: AppIntentTimelineProvider {
    typealias Intent = OffTimeWidgetConfigurationIntent
    typealias Entry = OffTimeEntry

    /// 组件侧诊断：读不到共享数据时在系统日志里留痕，便于用 Console.app / Xcode 定位
    /// 「组件一直没有数据」到底是 App 没发布过快照，还是 App Group 不可用。
    private static let logger = Logger(subsystem: "lt.offtime", category: "OffTimeProvider")

    func placeholder(in context: Context) -> OffTimeEntry {
        // 占位（redacted）渲染要跟真实条目「同形」：有共享数据就用真实城市，
        // 没有就用空态——两者都不含示例城市，避免用户看到「先显示了几个陌生城市，
        // 随后又变成空的」，大尺寸组件行数多，这种跳变最明显。
        // 只有预览（组件画廊 / Xcode）才用示例城市：预览环境读不到 App 写下的数据，
        // 给空态会让画廊里的大尺寸占位空掉一大片。
        OffTimeEntry(
            date: Date(),
            snapshot: WidgetSnapshotStore.load() ?? (context.isPreview ? .sample() : .empty())
        )
    }

    func snapshot(for configuration: OffTimeWidgetConfigurationIntent, in context: Context) async -> OffTimeEntry {
        OffTimeEntry(date: Date(), snapshot: snapshot(for: configuration, isPreview: context.isPreview))
    }

    func timeline(for configuration: OffTimeWidgetConfigurationIntent, in context: Context) async -> Timeline<OffTimeEntry> {
        let now = Date()
        let snapshot = snapshot(for: configuration)
        // 首个条目就是请求时刻，保证组件刚添加/刷新时立刻有可渲染条目；
        // 同时约定刷新期限：有数据时等分钟精度结束，没数据时段间隔重试（避免空态一直挂着）。
        let plan = WidgetTimelineSchedule.plan(from: now)
        let entries = plan.dates.map { date in
            OffTimeEntry(date: date, snapshot: snapshot)
        }
        let reloadDate = WidgetTimelineSchedule.reloadDate(
            after: now,
            hasCities: !snapshot.cities.isEmpty,
            plan: plan
        )
        return Timeline(entries: entries, policy: .after(reloadDate))
    }

    private func snapshot(for configuration: OffTimeWidgetConfigurationIntent, isPreview: Bool = false) -> WidgetSnapshot {
        // 读不到共享快照（App 还没发布过 / App Group 不可用）时给出空快照，
        // 让组件显示「打开 App 添加城市」，而不是拿设备时区伪造一个城市掩盖问题。
        // 例外：Xcode / 组件画廊预览本身读不到 App 写下的数据，用示例快照，避免预览空白。
        let stored = WidgetSnapshotStore.load()
        if stored == nil, !isPreview {
            Self.logger.error(
                "组件读不到共享快照：App Group 可用=\(WidgetSnapshotStore.isAppGroupAvailable, privacy: .public)"
            )
        }
        let base = stored ?? (isPreview ? .sample() : .empty())
        guard let selectedCities = configuration.cities, !selectedCities.isEmpty else {
            return base
        }

        var seenIDs = Set<String>()
        let selectedIDs = Set(selectedCities.map(\.id))
        var cities = base.cities.filter { selectedIDs.contains($0.id) }
        seenIDs.formUnion(cities.map(\.id))

        for entity in selectedCities {
            guard seenIDs.insert(entity.id).inserted else { continue }
            cities.append(entity.toSnapshot())
        }

        return WidgetSnapshot(
            cities: cities,
            localTimezoneId: base.localTimezoneId,
            use24Hour: base.use24Hour,
            updatedAt: base.updatedAt
        )
    }
}

struct OffTimeWidget: Widget {
    private let kind = "OffTimeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: OffTimeWidgetConfigurationIntent.self, provider: OffTimeProvider()) { entry in
            OffTimeWidgetView(entry: entry)
        }
        // 组件库里的名字跟随系统语言：中文 = 世界时钟、英文 = OffTime，
        // 与 App 名称（CFBundleDisplayName）保持一致，避免用户按「世界时钟」找不到组件。
        .configurationDisplayName(Text(String(
            localized: "widget.gallery.name",
            defaultValue: "OffTime"
        )))
        .description(Text(String(
            localized: "widget.gallery.description",
            defaultValue: "Shows the default order from your clock list; edit the widget to choose which cities to display"
        )))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct OffTimeMediumThreeCitiesWidget: Widget {
    private let kind = "OffTimeMediumThreeCitiesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: OffTimeWidgetConfigurationIntent.self,
            provider: OffTimeProvider()
        ) { entry in
            OffTimeWidgetView(entry: entry, showsThreeCities: true)
        }
        .configurationDisplayName(Text(String(
            localized: "widget.gallery.name",
            defaultValue: "OffTime"
        )))
        .description(Text(String(
            localized: "widget.gallery.description",
            defaultValue: "Shows the default order from your clock list; edit the widget to choose which cities to display"
        )))
        .supportedFamilies([
            .systemMedium
        ])
        .contentMarginsDisabled()
    }
}

struct OffTimeLargeWidget: Widget {
    private let kind = "OffTimeLargeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: OffTimeWidgetConfigurationIntent.self,
            provider: OffTimeProvider()
        ) { entry in
            OffTimeWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(String(
            localized: "widget.gallery.name",
            defaultValue: "OffTime"
        )))
        .description(Text(String(
            localized: "widget.gallery.description",
            defaultValue: "Shows the default order from your clock list; edit the widget to choose which cities to display"
        )))
        .supportedFamilies([
            .systemLarge
        ])
    }
}

struct OffTimeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: OffTimeEntry
    var showsThreeCities = false

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var cities: [WidgetCitySnapshot] { snapshot.cities }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                accessoryCircular
            case .accessoryRectangular:
                accessoryRectangular
            case .systemMedium:
                if showsThreeCities {
                    systemMediumThreeCities
                } else {
                    systemMedium
                }
            case .systemLarge:
                systemLarge
            default:
                systemSmall
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    // MARK: - 小尺寸
    //
    // 城市行（昼夜图标 + 城市名）
    //        大号时间
    //   星期 + 日期 · 与本地城市的关系

    private var systemSmall: some View {
        Group {
            if let city = cities.first {
                VStack(spacing: 0) {
                    titleRow(for: city)

                    Spacer(minLength: 4)

                    Text(timeText(for: city))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    dateRow(for: city, showsRelation: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
            } else {
                emptyState
            }
        }
    }

    // MARK: - 中尺寸
    //
    // 左右两列，每列自上而下：城市行 / 时间 / 星期日期（含与本地城市的关系），与小尺寸同构。

    private var systemMedium: some View {
        Group {
            if cities.isEmpty {
                emptyState
            } else {
                HStack(spacing: 14) {
                    cityColumn(cities[0])
                    if cities.count > 1 {
                        Divider()
                        cityColumn(cities[1])
                    }
                }
            }
        }
    }

    private func cityColumn(_ city: WidgetCitySnapshot) -> some View {
        VStack(spacing: 0) {
            titleRow(for: city)

            Spacer(minLength: 4)

            Text(timeText(for: city))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 4)

            dateRow(for: city, showsRelation: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 中尺寸（3 城）
    //
    // 纵向均分行高；不足 3 个城市时，剩余高度继续平分给现有城市行。

    private var systemMediumThreeCities: some View {
        let shownCities = Array(cities.prefix(3))
        return Group {
            if shownCities.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shownCities.enumerated()), id: \.element.id) { index, city in
                        mediumThreeCitiesRow(for: city)
                            .frame(maxHeight: .infinity)

                        if index < shownCities.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func mediumThreeCitiesRow(for city: WidgetCitySnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                titleRow(for: city, font: .headline)
                dateRow(for: city, showsRelation: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeText(for: city))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 大尺寸
    //
    // 每行：左侧城市信息（城市名 / 星期日期 · 与本地城市的关系），右侧大号时间。

    private var systemLarge: some View {
        let shown = Array(cities.prefix(6))
        return Group {
            if shown.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, city in
                        cityRow(city)
                            .frame(maxHeight: .infinity)
                        if index < shown.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func cityRow(_ city: WidgetCitySnapshot) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                titleRow(for: city)
                dateRow(for: city, showsRelation: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeText(for: city))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 行内组件

    /// 城市行：昼夜图标 + 城市名。
    /// 「与本地城市的关系」统一由日期行承载，三个尺寸位置一致。
    private func titleRow(for city: WidgetCitySnapshot, font: Font = .title3) -> some View {
        HStack(alignment: .top, spacing: 6) {
            daypartIcon(for: city)

            Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn))
                .font(font)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.6)
        }
    }

    /// 与本地城市的关系：始终展示时差；0h 也直接展示。
    /// 时差由调用方传入（`dateRow` 已经算过），避免同一行重复计算。
    private func relation(
        for city: WidgetCitySnapshot,
        difference: (offset: String, crossDay: String?)?
    ) -> (text: String, color: Color)? {
        guard let difference, !difference.offset.isEmpty else { return nil }
        return (difference.offset, .secondary)
    }

    /// 星期 + 日期（+ 跨天标记）。
    /// `showsRelation` 为真时在行尾接上「与本地城市的关系」——三个尺寸的时差/本地都放在这里，
    /// 紧跟在日期后面一起读，城市行则留给更大的城市名。
    private func dateRow(for city: WidgetCitySnapshot, showsRelation: Bool = false) -> some View {
        // 跨天标记和行尾的时差都来自同一次计算；大尺寸要渲染 6 行，重复计算会成倍放大开销。
        let difference = timeDifference(for: city)

        return HStack(spacing: 4) {
            if let crossDay = difference?.crossDay {
                crossDayBadge(crossDay)
            }

            // 星期日期与时差的字体样式互换：日期用中黑 + 等宽数字，时差回到普通字重
            Text(weekdayAndDateText(for: city))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if showsRelation, let relation = relation(for: city, difference: difference) {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(relation.text)
                    .foregroundStyle(relation.color)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func crossDayBadge(_ text: String) -> some View {
        labelBadge(text, color: .orange)
    }

    private func labelBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    /// 昼夜图标：白天太阳（橙），夜晚月亮（靛）。
    private func daypartIcon(for city: WidgetCitySnapshot) -> some View {
        let isDaytime = TimezoneService.shared.isDaytime(timezoneId: city.timezoneId, date: entry.date)

        return Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
            .font(.system(size: 10))
            .foregroundStyle(isDaytime ? Color.orange : Color.indigo)
            .accessibilityLabel(Text(isDaytime
                ? String(localized: "widget.daytime", defaultValue: "Daytime")
                : String(localized: "widget.nighttime", defaultValue: "Nighttime")))
    }

    // MARK: - Lock Screen Widgets

    private var accessoryCircular: some View {
        Group {
            if let city = cities.first {
                VStack(spacing: 0) {
                    Text(shortTimeText(for: city))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(displayName(for: city))
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .combine)
            } else {
                Image(systemName: "globe")
            }
        }
    }

    private var accessoryRectangular: some View {
        let shownCities = Array(cities.prefix(3))
        let fontSize: CGFloat = switch shownCities.count {
        case 0, 1: 20
        case 2: 17
        default: 14
        }

        return VStack(alignment: .leading, spacing: shownCities.count == 3 ? 1 : 3) {
            ForEach(shownCities) { city in
                HStack(spacing: 6) {
                    Text(displayName(for: city))
                        .font(.system(size: fontSize, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(-2)
                        .minimumScaleFactor(0.5)
                    Spacer(minLength: 4)
                    Text(timeText(for: city))
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.title3)
            Text(String(localized: "widget.empty.title", defaultValue: "Open OffTime to add a city"))
                .font(.caption)
                .multilineTextAlignment(.center)
            Text(String(localized: "widget.empty.subtitle", defaultValue: "Cities you add in the app show up here"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var widgetBackground: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            AccessoryWidgetBackground()
        default:
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Formatting

    private func displayName(for city: WidgetCitySnapshot) -> String {
        CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn)
    }

    private func timeText(for city: WidgetCitySnapshot) -> String {
        TimezoneService.shared.getWidgetTime(
            timezoneId: city.timezoneId,
            use24Hour: snapshot.use24Hour,
            date: entry.date
        ) ?? "--:--"
    }

    private func shortTimeText(for city: WidgetCitySnapshot) -> String {
        guard let time = TimezoneService.shared.getLocalTime24(timezoneId: city.timezoneId, date: entry.date) else {
            return "--:--"
        }
        let parts = time.split(separator: ":")
        guard parts.count == 2 else { return time }
        return "\(parts[0]):\(parts[1])"
    }

    private func dateText(for city: WidgetCitySnapshot) -> String {
        TimezoneService.shared.getMonthDayOnly(timezoneId: city.timezoneId, date: entry.date) ?? ""
    }

    /// 「周几 + 月日」：月日文本来自 `getMonthDayOnly`（不含星期），保证星期只出现一次。
    private func weekdayAndDateText(for city: WidgetCitySnapshot) -> String {
        let weekday = TimezoneService.shared.getLocalWeekday(timezoneId: city.timezoneId, date: entry.date) ?? ""
        let date = dateText(for: city)
        return [weekday, date].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 与本地城市的时差和跨天提示；同一时区返回 0h。
    private func timeDifference(for city: WidgetCitySnapshot) -> (offset: String, crossDay: String?)? {
        let difference = TimezoneService.shared.getTimeDifferenceBetween(
            sourceTimezoneId: snapshot.localTimezoneId,
            targetTimezoneId: city.timezoneId,
            date: entry.date
        )
        return difference.offset.isEmpty ? nil : difference
    }
}
