import SwiftUI

struct TravelSectionHeader: View {
    let icon: String
    let titleKey: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundColor(.accentColor)
            Text(titleKey)
                .font(.body.weight(.semibold))
            Spacer()
        }
    }
}

struct TravelErrorView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.orange.opacity(0.12))
            .cornerRadius(16)
    }
}
