import SwiftUI

struct TravelAdviceSection: View {
    let plan: TravelPlan
    let activeLegIndex: Int
    let legCount: Int

    var body: some View {
        VStack(spacing: 16) {
            adviceCard
            reminderCard
        }
    }

    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TravelSectionHeader(
                icon: "moon.zzz",
                titleKey: "travel.jetlag.title"
            )

            if legCount > 1 {
                Text("\(String(format: String(localized: "travel.leg.format"), activeLegIndex + 1)) · \(plan.destinationName)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            adviceRow(
                icon: "hourglass",
                titleKey: "travel.phase.inflight",
                text: levelText(plan.adjustmentLevel)
            )
            adviceRow(
                icon: "sun.and.horizon",
                titleKey: "travel.phase.arrival",
                text: directionAdviceText(plan.direction)
            )
            adviceRow(
                icon: "calendar.badge.clock",
                titleKey: "travel.phase.followup",
                textKey: "travel.advice.followup"
            )
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TravelSectionHeader(
                icon: "bell.badge",
                titleKey: "travel.arrival.title"
            )

            adviceRow(icon: "drop", textKey: "travel.reminder.water")
            adviceRow(icon: "sun.max", textKey: "travel.reminder.light")
            adviceRow(icon: "cup.and.saucer", textKey: "travel.reminder.caffeine")
            adviceRow(icon: "timer", textKey: "travel.reminder.nap")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func adviceRow(
        icon: String,
        titleKey: LocalizedStringKey,
        textKey: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(textKey)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adviceRow(
        icon: String,
        titleKey: LocalizedStringKey,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adviceRow(icon: String, textKey: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.accentColor)
                .frame(width: 22)
            Text(textKey)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelText(_ level: TravelAdjustmentLevel) -> String {
        switch level {
        case .none: return String(localized: "travel.advice.none")
        case .small: return String(localized: "travel.advice.small")
        case .medium: return String(localized: "travel.advice.medium")
        case .large: return String(localized: "travel.advice.large")
        }
    }

    private func directionAdviceText(_ direction: TravelDirection) -> String {
        switch direction {
        case .same: return String(localized: "travel.advice.same")
        case .behind: return String(localized: "travel.advice.behind")
        case .ahead: return String(localized: "travel.advice.ahead")
        }
    }
}
