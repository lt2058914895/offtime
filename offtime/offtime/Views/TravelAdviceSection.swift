import SwiftUI

/// 作息调整建议：一张卡片内突出「作息计划」，合并行程阶段建议与关键提醒。
struct TravelAdviceSection: View {
    let plan: TravelPlan
    let activeLegIndex: Int
    let legCount: Int

    var body: some View {
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

            schedulePlanBox

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

            Divider()

            Text(String(localized: "travel.arrival.title"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            adviceRow(icon: "drop", textKey: "travel.reminder.water")
            adviceRow(icon: "sun.max", textKey: "travel.reminder.light")
            adviceRow(icon: "cup.and.saucer", textKey: "travel.reminder.caffeine")
            adviceRow(icon: "timer", textKey: "travel.reminder.nap")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    /// 作息计划：目的地 + 固定起床/入睡时间，突出本段行程的关键作息。
    private var schedulePlanBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "travel.schedule.plan"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.accentColor)
            Text(String(
                format: String(localized: "travel.schedule.plan.format"),
                plan.destinationName,
                plan.wakeTime.text,
                plan.sleepTime.text
            ))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.10))
        .cornerRadius(12)
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
                    .foregroundColor(.primary)
                Text(textKey)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.primary)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
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
