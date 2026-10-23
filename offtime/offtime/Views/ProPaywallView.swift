import SwiftUI

struct ProPaywallView: View {
    @EnvironmentObject private var proAccessService: ProAccessService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

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
                    .disabled(proAccessService.isProcessing)
                }
            }
            .toast(message: Binding(
                get: { proAccessService.statusMessage },
                set: { _ in proAccessService.statusMessage = nil }
            ))
            .task {
                await proAccessService.refreshEntitlements()
                await proAccessService.refreshProductsIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await proAccessService.refreshEntitlements()
                    await proAccessService.refreshProductsIfNeeded()
                }
            }
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
            if proAccessService.isRestoring {
                restoringRow
            } else {
                if proAccessService.isUnlocked {
                    Text(String(localized: "pro.status.unlocked"))
                        .font(.headline)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 15)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(14)
                } else {
                    purchaseButton
                }

                if shouldShowProductRetry {
                    productRetryHint
                }
            }

            Text(String(localized: "pro.purchase.note"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var restoringRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text(String(localized: "pro.restore.processing"))
                .font(.headline)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.accentColor)
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
    }

    private var shouldShowProductRetry: Bool {
        proAccessService.product == nil
            && proAccessService.hasAttemptedProductLoad
            && !proAccessService.isLoadingProducts
            && !proAccessService.isUnlocked
    }

    private var productRetryHint: some View {
        VStack(spacing: 6) {
            Text(String(localized: "pro.product.unavailable"))
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                Task { await proAccessService.reloadProducts() }
            } label: {
                Text(String(localized: "pro.product.retry"))
                    .font(.footnote.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
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
            HStack(spacing: 8) {
                if proAccessService.isPurchasing {
                    ProgressView()
                        .tint(.white)
                    Text(String(localized: "pro.purchase.processing"))
                        .font(.headline)
                } else if proAccessService.isLoadingProducts {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(String(localized: "pro.purchase"))
                        .font(.headline)

                    if let priceText = proAccessService.priceText {
                        Text(priceText)
                            .font(.headline)
                    }
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
