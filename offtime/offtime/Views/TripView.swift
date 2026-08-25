import SwiftUI
import SwiftData
import Combine

/// 行程列表：按「进行中 / 未开始 / 已结束」分组展示所有已保存行程。
/// 可从设置页「行程」进入，也可从行程 Tab 的「我的行程」进入。
struct TripView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TripModel.updatedAt, order: .reverse) private var trips: [TripModel]
    @State private var now = Date()
    @State private var tripToDelete: TripModel?

    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private struct StatusGroup: Identifiable {
        let status: TripStatus
        let trips: [TripModel]
        var id: TripStatus { status }
    }

    var body: some View {
        Group {
            if trips.isEmpty {
                ContentUnavailableView(
                    String(localized: "trip.list.empty.title"),
                    systemImage: "airplane",
                    description: Text(String(localized: "trip.list.empty"))
                )
            } else {
                List {
                    Section {
                    } header: {
                        Text(String(localized: "trip.list.swipe.hint"))
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .textCase(nil)
                    }
                    ForEach(grouped) { group in
                        Section {
                            ForEach(group.trips) { trip in
                                row(for: trip)
                            }
                            .onDelete { offsets in
                                guard let first = offsets.first else { return }
                                tripToDelete = group.trips[first]
                            }
                        } header: {
                            Text(group.status.displayName)
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "tab.travel"))
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
            now = Date()
        }
        .onReceive(refreshTimer) { _ in
            now = Date()
        }
        .confirmationDialog(
            String(localized: "trip.delete.confirm.title"),
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: tripToDelete
        ) { trip in
            Button(String(localized: "trip.delete"), role: .destructive) {
                modelContext.delete(trip)
                try? modelContext.save()
                tripToDelete = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                tripToDelete = nil
            }
        } message: { trip in
            Text(trip.routeText)
        }
    }

    private var grouped: [StatusGroup] {
        let statuses: [TripStatus] = [.ongoing, .upcoming, .finished]
        return statuses.compactMap { status in
            let items = trips
                .filter { $0.status(at: now) == status }
                .sorted { first, second in
                    let lhs = first.firstDeparture ?? .distantPast
                    let rhs = second.firstDeparture ?? .distantPast
                    return status == .finished ? lhs > rhs : lhs < rhs
                }
            return items.isEmpty ? nil : StatusGroup(status: status, trips: items)
        }
    }

    private func row(for trip: TripModel) -> some View {
        let status = trip.status(at: now)
        let isFinished = status == .finished

        return NavigationLink {
            TravelView(initialTripID: trip.id, isEmbedded: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: status))
                    .font(.title3)
                    .foregroundColor(color(for: status))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(trip.routeText)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if status == .ongoing {
                            Text(status.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(dateChainText(for: trip))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .opacity(isFinished ? 0.55 : 1)
        }
    }

    private func icon(for status: TripStatus) -> String {
        switch status {
        case .ongoing: return "airplane.circle.fill"
        case .upcoming: return "calendar.badge.clock"
        case .finished: return "checkmark.circle"
        }
    }

    private func color(for status: TripStatus) -> Color {
        switch status {
        case .ongoing: return .green
        case .upcoming: return .blue
        case .finished: return Color(.systemGray)
        }
    }

    /// 单段行程显示「出发 – 结束」；多段行程按城市顺序串联日期：8月1日 → 8月5日 → 8月10日。
    private func dateChainText(for trip: TripModel) -> String {
        guard let firstDeparture = trip.firstDeparture else { return "" }

        if trip.legs.count <= 1 {
            return "\(dateText(firstDeparture)) – \(dateText(trip.tripEndDate))"
        }

        var dates = [firstDeparture] + trip.legs.map(\.arrivalDate)
        dates[dates.count - 1] = trip.tripEndDate
        return dates.map { dateText($0) }.joined(separator: " → ")
    }

    private func dateText(_ date: Date) -> String {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let year = calendar.component(.year, from: date)
        if year == currentYear {
            return date.formatted(.dateTime.month(.defaultDigits).day())
        }
        return date.formatted(.dateTime.year().month(.defaultDigits).day())
    }
}

#Preview {
    NavigationStack {
        TripView()
    }
    .modelContainer(for: TripModel.self, inMemory: true)
}
