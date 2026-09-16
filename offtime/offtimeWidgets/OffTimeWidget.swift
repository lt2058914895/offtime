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
            defaultValue: "See the current time in several cities; the order matches your clock list"
        )))
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct OffTimeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: OffTimeEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var cities: [WidgetCitySnapshot] { snapshot.cities }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                accessoryCircular
            case .accessoryRectangular:
                accessoryRectangular
            case .accessoryInline:
                accessoryInline
            case .systemMedium:
                systemMedium
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
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
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
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Spacer(minLength: 4)

            dateRow(for: city, showsRelation: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                titleRow(for: city, showsEnglishName: true)
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

    /// 城市行：昼夜图标 + 城市名（大尺寸附带英文名）。
    /// 「与本地城市的关系」统一由日期行承载，三个尺寸位置一致。
    private func titleRow(for city: WidgetCitySnapshot, showsEnglishName: Bool = false) -> some View {
        HStack(spacing: 6) {
            daypartIcon(for: city)

            Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn))
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if showsEnglishName,
               let secondaryName = CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn) {
                Text(secondaryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// 与本地城市的关系：本地 → 「本地」，其他城市 → 时差，同一时区 → nil。
    /// 时差由调用方传入（`dateRow` 已经算过），避免同一行重复计算。
    private func relation(
        for city: WidgetCitySnapshot,
        difference: (offset: String, crossDay: String?)?
    ) -> (text: String, color: Color)? {
        if city.isLocal {
            return (String(localized: "widget.city.local", defaultValue: "Local"), .accentColor)
        }
        guard let difference, difference.offset != "0h" else { return nil }
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
                VStack(spacing: 1) {
                    Text(shortTimeText(for: city))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(displayName(for: city))
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Image(systemName: "globe")
            }
        }
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(cities.prefix(2)) { city in
                HStack(spacing: 6) {
                    Text(displayName(for: city))
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timeText(for: city))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var accessoryInline: some View {
        Text(
            cities.prefix(2)
                .map { "\(displayName(for: $0)) \(timeText(for: $0))" }
                .joined(separator: " · ")
        )
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
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
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
        let timezoneService = TimezoneService.shared
        if snapshot.use24Hour {
            return timezoneService.getLocalTime24(timezoneId: city.timezoneId, date: entry.date) ?? "--:--"
        }
        return timezoneService.getLocalTime12(timezoneId: city.timezoneId, date: entry.date) ?? "--:--"
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

    /// 与本地城市的时差和跨天提示；本地城市或同一时区返回 nil。
    private func timeDifference(for city: WidgetCitySnapshot) -> (offset: String, crossDay: String?)? {
        guard city.timezoneId != snapshot.localTimezoneId else { return nil }

        let difference = TimezoneService.shared.getTimeDifferenceBetween(
            sourceTimezoneId: snapshot.localTimezoneId,
            targetTimezoneId: city.timezoneId,
            date: entry.date
        )
        return difference.offset == "0h" ? nil : difference
    }
}
