import SwiftUI

struct TravelSummarySection: View {
    let itinerary: TravelItinerary

    var body: some View {
        VStack(spacing: 14) {
            Text(itinerary.routeNames.joined(separator: " → "))
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            VStack(spacing: 12) {
                ForEach(Array(itinerary.plans.enumerated()), id: \.offset) { index, plan in
                    VStack(spacing: 10) {
                        HStack {
                            Text(String(format: String(localized: "travel.leg.format"), index + 1))
                                .font(.caption.weight(.bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(plan.originName) → \(plan.destinationName)")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            summaryMetric(
                                value: plan.offsetText,
                                titleKey: "travel.summary.difference",
                                color: .blue
                            )
                            summaryMetric(
                                value: plan.flightDurationText,
                                titleKey: "travel.summary.duration",
                                color: .accentColor
                            )
                            summaryMetric(
                                value: String(
                                    format: String(localized: "travel.segment.days.format"),
                                    plan.tripDays
                                ),
                                titleKey: "travel.summary.segment.time",
                                color: .purple
                            )
                            summaryMetric(
                                value: recoveryText(plan.adjustmentLevel),
                                titleKey: "travel.summary.recovery",
                                color: .green
                            )
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.55))
                    .cornerRadius(14)

                    if index != itinerary.plans.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func summaryMetric(
        value: String,
        titleKey: LocalizedStringKey,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recoveryText(_ level: TravelAdjustmentLevel) -> String {
        switch level {
        case .none: return String(localized: "travel.recovery.none")
        case .small: return String(localized: "travel.recovery.small")
        case .medium: return String(localized: "travel.recovery.medium")
        case .large: return String(localized: "travel.recovery.large")
        }
    }
}
