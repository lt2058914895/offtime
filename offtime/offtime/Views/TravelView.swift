import SwiftUI

struct TravelView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    featureHero(
                        icon: "airplane",
                        titleKey: "travel.title",
                        descriptionKey: "travel.subtitle"
                    )

                    featureCard(
                        icon: "arrow.triangle.branch",
                        titleKey: "travel.route.title",
                        descriptionKey: "travel.route.description"
                    )
                    featureCard(
                        icon: "moon.zzz",
                        titleKey: "travel.jetlag.title",
                        descriptionKey: "travel.jetlag.description"
                    )
                    featureCard(
                        icon: "bell.badge",
                        titleKey: "travel.arrival.title",
                        descriptionKey: "travel.arrival.description"
                    )
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "tab.travel"))
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
