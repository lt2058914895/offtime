import SwiftUI

struct ProPaywallView: View {
    @EnvironmentObject private var proAccessService: ProAccessService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    featureList
                    purchaseSection
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(String(localized: "common.close"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await proAccessService.restore() }
                    } label: {
                        Text(String(localized: "pro.restore"))
                    }
                }
            }
            .toast(message: Binding(
                get: { proAccessService.statusMessage },
                set: { _ in proAccessService.statusMessage = nil }
            ))
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(AppDisplay.text("pro.paywall.headline", AppDisplay.name))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private var featureList: some View {
        VStack(spacing: 12) {
            featureRow(
                title: String(localized: "pro.feature.themes.title")
            )
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(18)
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if proAccessService.isUnlocked {
                if proAccessService.isLegacyUnlocked {
                    Text(String(localized: "pro.status.legacy.hint"))
                        .font(.headline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "pro.status.unlocked"))
                        .font(.headline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 15)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(14)
                }
            } else {
                purchaseButton
            }

            if proAccessService.isLegacyUnlocked {
                legacyPurchaseNote

                purchaseButton
            }

            Text(String(localized: "pro.purchase.note"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legacyPurchaseNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(String(localized: "pro.purchase.note.legacy.label"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "pro.purchase.note.legacy.detail"))

                Text(String(localized: "pro.legacy.purchase.prompt"))
                    .foregroundStyle(Color.orange)
            }
            .font(.caption)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var purchaseButton: some View {
        Button {
            Task {
                await proAccessService.purchase()
                if proAccessService.isUnlocked {
                    dismiss()
                }
            }
        } label: {
            HStack {
                if proAccessService.isLoadingProducts {
                    ProgressView()
                } else {
                    Text(String(localized: "pro.purchase"))
                        .font(.headline)
                }

                if let priceText = proAccessService.priceText {
                    Text(priceText)
                        .font(.headline)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.accentColor)
            .cornerRadius(14)
        }
        .disabled(proAccessService.product == nil)
    }

    private func featureRow(title: String, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ProPaywallView()
        .environmentObject(ProAccessService())
}
