import SwiftUI

struct TravelTimelineSection: View {
    let plan: TravelPlan
    let itinerary: TravelItinerary
    let activeLegIndex: Int
    let onSelectLeg: (Int) -> Void

    private let timezoneService = TimezoneService.shared

    var body: some View {
        VStack(spacing: 12) {
            TravelSectionHeader(
                icon: "chart.axis.columns",
                titleKey: "travel.timeline.title"
            )

            if itinerary.plans.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(itinerary.plans.enumerated()), id: \.offset) { index, segmentPlan in
                            segmentChip(
                                index: index,
                                destinationName: segmentPlan.destinationName,
                                isActive: index == activeLegIndex
                            ) {
                                onSelectLeg(index)
                            }
                        }
                    }
                }
            }

            HStack {
                Text(plan.destinationName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(plan.originName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            let visibleEvents = timelineEvents

            VStack(spacing: 12) {
                ForEach(timelineGroups(events: visibleEvents)) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(dayTitle(day.dayIndex, events: day.events))
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(dayDate(day.events))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 0) {
                            ForEach(day.events) { event in
                                timelineRow(event)
                                if event.id != day.events.last?.id {
                                    Divider()
                                        .padding(.leading, 82)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.55))
                    .cornerRadius(14)
                }

                let remainingDays = plan.tripDays - displayedDayCount
                if remainingDays > 0 {
                    Label(
                        String(
                            format: String(localized: "travel.timeline.remaining.format"),
                            remainingDays,
                            plan.wakeTime.text,
                            plan.sleepTime.text
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.footnote)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.green.opacity(0.10))
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var timelineEvents: [TravelTimelineEvent] {
        plan.timeline.filter { $0.dayIndex <= displayedDayCount }
    }

    private var displayedDayCount: Int {
        min(plan.tripDays, 2)
    }

    private func segmentChip(
        index: Int,
        destinationName: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text("\(index + 1) · \(destinationName)")
                .font(.caption.weight(.semibold))
                .foregroundColor(isActive ? .white : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(isActive ? Color.accentColor : Color(.systemGray6))
                .clipShape(Capsule())
        }
    }

    private func timelineRow(_ event: TravelTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeText(event.destinationDate, timezoneId: plan.destinationTimezoneId))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundColor(.primary)
                .frame(width: 58, alignment: .leading)

            Image(systemName: eventIcon(event.kind))
                .font(.caption.weight(.bold))
                .foregroundColor(eventColor(event.kind))
                .frame(width: 24, height: 24)
                .background(eventColor(event.kind).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(eventTitle(event.kind))
                    .font(.body.weight(.semibold))
                Text("\(plan.originName) \(timeText(event.originDate, timezoneId: plan.originTimezoneId))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(isFlightEvent(event.kind) ? Color.accentColor.opacity(0.06) : .clear)
        .cornerRadius(10)
        .accessibilityElement(children: .combine)
    }

    private func timelineGroups(events: [TravelTimelineEvent]) -> [TimelineDay] {
        Dictionary(grouping: events, by: { $0.dayIndex })
            .map { TimelineDay(dayIndex: $0.key, events: $0.value) }
            .sorted { $0.dayIndex < $1.dayIndex }
    }

    private func dayTitle(
        _ dayIndex: Int,
        events: [TravelTimelineEvent]
    ) -> String {
        if dayIndex == 1 && events.contains(where: { $0.kind == .arrival }) {
            return String(format: String(localized: "travel.day.arrival.format"), dayIndex)
        }
        return String(format: String(localized: "travel.day.format"), dayIndex)
    }

    private func dayDate(_ events: [TravelTimelineEvent]) -> String {
        guard let date = events.first?.destinationDate else { return "" }
        return timezoneService.getMonthDay(
            timezoneId: plan.destinationTimezoneId,
            date: date
        ) ?? ""
    }

    private func timeText(_ date: Date, timezoneId: String) -> String {
        timezoneService.getLocalizedTime(timezoneId: timezoneId, date: date) ?? ""
    }

    private func eventTitle(_ kind: TravelTimelineEventKind) -> String {
        switch kind {
        case .departure: return String(localized: "travel.event.departure")
        case .arrival: return String(localized: "travel.event.arrival")
        case .wake: return String(localized: "travel.event.wake")
        case .daylight: return String(localized: "travel.event.daylight")
        case .sleep: return String(localized: "travel.event.sleep")
        }
    }

    private func eventIcon(_ kind: TravelTimelineEventKind) -> String {
        switch kind {
        case .departure: return "airplane.departure"
        case .arrival: return "airplane.arrival"
        case .wake: return "sunrise"
        case .daylight: return "sun.max"
        case .sleep: return "moon.zzz"
        }
    }

    private func eventColor(_ kind: TravelTimelineEventKind) -> Color {
        switch kind {
        case .departure, .arrival: return .accentColor
        case .wake: return .orange
        case .daylight: return .yellow
        case .sleep: return .indigo
        }
    }

    private func isFlightEvent(_ kind: TravelTimelineEventKind) -> Bool {
        kind == .departure || kind == .arrival
    }
}

private struct TimelineDay: Identifiable {
    let dayIndex: Int
    let events: [TravelTimelineEvent]

    var id: Int { dayIndex }
}
