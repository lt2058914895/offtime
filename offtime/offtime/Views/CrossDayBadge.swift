import SwiftUI

struct CrossDayBadge: View {
    let label: String

    private var isTomorrow: Bool {
        label == String(localized: "clock.tomorrow")
    }

    private var badgeColor: Color {
        isTomorrow ? .teal : .purple
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.13))
            .foregroundColor(badgeColor)
            .clipShape(Capsule())
    }
}
