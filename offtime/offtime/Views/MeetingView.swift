import SwiftUI

struct MeetingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    featureHero(
                        icon: "person.2",
                        titleKey: "meeting.title",
                        descriptionKey: "meeting.subtitle"
                    )

                    featureCard(
                        icon: "clock.badge.checkmark",
                        titleKey: "meeting.timeline.title",
                        descriptionKey: "meeting.timeline.description"
                    )
                    featureCard(
                        icon: "sparkles",
                        titleKey: "meeting.suggestions.title",
                        descriptionKey: "meeting.suggestions.description"
                    )
                    featureCard(
                        icon: "calendar.badge.plus",
                        titleKey: "meeting.share.title",
                        descriptionKey: "meeting.share.description"
                    )
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "tab.meeting"))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func featureHero(icon: String, titleKey: LocalizedStringKey, descriptionKey: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(titleKey)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(descriptionKey)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.accentColor.opacity(0.10))
        .cornerRadius(16)
    }

    private func featureCard(icon: String, titleKey: LocalizedStringKey, descriptionKey: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(titleKey)
                    .font(.body.weight(.semibold))
                Text(descriptionKey)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}
