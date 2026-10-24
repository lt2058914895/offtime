import SwiftUI

struct WidgetStylePreviewView: View {
    let cities: [WidgetCitySnapshot]
    let localTimezoneId: String
    let use24Hour: Bool
    let date: Date
    let theme: ThemeStyleConfiguration?

    var body: some View {
        Group {
            if cities.isEmpty {
                emptyState
            } else {
                HStack(spacing: 14) {
                    widgetCityColumn(cities[0])

                    if cities.count > 1 {
                        Divider()
                        widgetCityColumn(cities[1])
                    }
                }
            }
        }
        .padding(14)
        .frame(height: 158)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .foregroundStyle(theme?.resolvedAccentColor ?? Color.primary)
        .tint(theme?.resolvedAccentColor ?? Color.accentColor)
    }

    private func widgetCityColumn(_ city: WidgetCitySnapshot) -> some View {
        let difference = timeDifference(for: city)
        return VStack(spacing: 0) {
            widgetTitleRow(for: city)

            Spacer(minLength: 4)

            widgetTimeBlock(for: city, difference: difference)

            Spacer(minLength: 4)

            widgetDateRow(for: city, difference: difference)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func widgetTitleRow(for city: WidgetCitySnapshot) -> some View {
        Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn))
            .font(.title3)
            .fontWeight(.semibold)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.6)
    }

    private func widgetTimeBlock(
        for city: WidgetCitySnapshot,
        difference: (offset: String, crossDay: String?)
    ) -> some View {
        VStack(spacing: 3) {
            Text(timeText(for: city))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let crossDay = difference.crossDay {
                crossDayBadge(crossDay)
            }
        }
    }

    private func widgetDateRow(
        for city: WidgetCitySnapshot,
        difference: (offset: String, crossDay: String?)
    ) -> some View {
        HStack(spacing: 4) {
            Text(dateAndWeekdayText(for: city))
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if !difference.offset.isEmpty {
                Text("·")
                    .foregroundStyle(.tertiary)

                Text(difference.offset)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.title3)

            Text(String(localized: "custom.theme.preview.empty.title", defaultValue: "No cities yet"))
                .font(.caption)

            Text(String(localized: "custom.theme.preview.empty.subtitle", defaultValue: "Add cities to preview your theme"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewBackground: ThemeWidgetBackground {
        ThemeWidgetBackground(
            color: theme?.backgroundColor,
            photo: theme?.backgroundPhoto
        )
    }

    private func timeText(for city: WidgetCitySnapshot) -> String {
        TimezoneService.shared.getWidgetTime(
            timezoneId: city.timezoneId,
            use24Hour: use24Hour,
            date: date
        ) ?? "--:--"
    }

    private func dateAndWeekdayText(for city: WidgetCitySnapshot) -> String {
        let weekday = TimezoneService.shared.getLocalWeekday(timezoneId: city.timezoneId, date: date) ?? ""
        let dateText = TimezoneService.shared.getMonthDayOnly(timezoneId: city.timezoneId, date: date) ?? ""
        return [dateText, weekday].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func timeDifference(for city: WidgetCitySnapshot) -> (offset: String, crossDay: String?) {
        TimezoneService.shared.getTimeDifferenceBetween(
            sourceTimezoneId: localTimezoneId,
            targetTimezoneId: city.timezoneId,
            date: date
        )
    }

    private func crossDayBadge(_ text: String) -> some View {
        badge(text, color: theme?.resolvedAccentColor ?? .secondary)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
