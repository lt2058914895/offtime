import SwiftUI

// MARK: - TimelineBar（详情页 24 小时色条）

struct TimelineBar: View {
    let hourlyHighlight: [Bool]
    let highlightColor: Color
    let nowHour: Double?

    var body: some View {
        VStack(spacing: 3) {
            Canvas { context, size in
                let segW = size.width / 24
                let h = size.height
                for hour in 0..<24 {
                    let x = CGFloat(hour) * segW
                    let rect = CGRect(x: x, y: 0, width: max(segW - 1, 1), height: h)
                    let color: Color = hourlyHighlight[hour] ? highlightColor : Color(.systemGray5)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
                if let now = nowHour {
                    let nowX = CGFloat(now) * segW
                    let marker = CGRect(x: nowX - 1, y: -2, width: 2, height: h + 4)
                    context.fill(Path(roundedRect: marker, cornerRadius: 1), with: .color(.red))
                }
            }
            .frame(height: 14)

            HStack {
                Text("0").font(.system(size: 9))
                Spacer()
                Text("6").font(.system(size: 9))
                Spacer()
                Text("12").font(.system(size: 9))
                Spacer()
                Text("18").font(.system(size: 9))
                Spacer()
                Text("24").font(.system(size: 9))
            }
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - CityDetailView

struct CityDetailView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CityDetailViewModel

    init(city: CityModel) {
        _viewModel = StateObject(wrappedValue: CityDetailViewModel(city: city))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                localWorkHoursCard
                targetWorkHoursCard
                overlapCard
                rulesCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.city.cityName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            viewModel.use24Hour = appEnvironment.settings.use24Hour
        }
        .onDisappear {
            viewModel.saveWorkHours()
            appEnvironment.citiesRevision += 1
        }
    }

    // MARK: - Local Work Hours

    private var localWorkHoursCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "house")
                        .foregroundColor(.accentColor)
                    Text(String(localized: "detail.local.work.hours"))
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(viewModel.localTime)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(String(localized: "detail.current.time"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                TimelineBar(
                    hourlyHighlight: viewModel.localHourlyWorking,
                    highlightColor: .accentColor,
                    nowHour: viewModel.localNowHour
                )
                workHoursSteppers(start: $viewModel.localWorkStart, end: $viewModel.localWorkEnd)
            }
        }
    }

    private var timeDifferenceColor: Color {
        let offset = viewModel.timeDifference
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }

    // MARK: - Target Work Hours

    private var targetWorkHoursCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "building.2")
                        .font(.title2)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.city.cityName)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(viewModel.city.cityEn)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.cityTime)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text(String(localized: "detail.current.time"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text(String(localized: "detail.time.diff"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(viewModel.timeDifference)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(timeDifferenceColor)
                        }
                    }
                }
                TimelineBar(
                    hourlyHighlight: viewModel.targetHourlyWorking,
                    highlightColor: .blue,
                    nowHour: viewModel.targetNowHour
                )
                workHoursSteppers(start: $viewModel.targetWorkStart, end: $viewModel.targetWorkEnd)
            }
        }
    }

    // MARK: - Overlap

    private var overlapCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: viewModel.overlap.isCurrentlyOverlapping ? "phone.fill" : "phone")
                        .foregroundColor(viewModel.overlap.isCurrentlyOverlapping ? .green : .secondary)
                    Text(String(localized: "detail.contactable.period"))
                        .font(.headline)
                    Spacer()
                    if viewModel.overlap.isCurrentlyOverlapping {
                        Text(String(localized: "detail.contactable.now"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
                TimelineBar(
                    hourlyHighlight: viewModel.overlap.hourlyOverlap,
                    highlightColor: .green,
                    nowHour: viewModel.localNowHour
                )
                Text(viewModel.overlapSummary)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundColor(viewModel.overlap.isCurrentlyOverlapping ? .green : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(viewModel.overlap.isCurrentlyOverlapping ? Color.green.opacity(0.12) : Color(.tertiarySystemFill))
                    .cornerRadius(10)
            }
        }
    }

    // MARK: - Rules

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "detail.rules.title"))
                .font(.headline)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                bulletText("detail.rules.1")
                bulletText("detail.rules.2")
                bulletText("detail.rules.3")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Components

    private func bulletText(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func workHoursSteppers(start: Binding<Int>, end: Binding<Int>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "detail.work.start"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(value: start, in: 0...23) {
                    Text(String(format: "%02d:00", start.wrappedValue))
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(localized: "detail.work.end"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(value: end, in: 1...24) {
                    Text(String(format: "%02d:00", end.wrappedValue))
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
    }
}
