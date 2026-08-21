import SwiftUI

struct TravelInputSection: View {
    @ObservedObject var viewModel: TravelViewModel
    @Binding var selectedLegID: UUID?
    @Binding var selectingOrigin: Bool
    @Binding var showCitySelector: Bool

    var body: some View {
        VStack(spacing: 12) {
            ForEach($viewModel.legs) { $leg in
                legEditor($leg)
            }

            Button(action: viewModel.addLeg) {
                Label(String(localized: "travel.add.leg"), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)

            Divider()

            HStack(spacing: 12) {
                schedulePicker(
                    titleKey: "travel.schedule.wake",
                    time: viewModel.wakeTime
                ) {
                    viewModel.updateWakeTime($0)
                }

                schedulePicker(
                    titleKey: "travel.schedule.sleep",
                    time: viewModel.sleepTime
                ) {
                    viewModel.updateSleepTime($0)
                }
            }

            DatePicker(
                selection: Binding(
                    get: { viewModel.tripEndDate },
                    set: { viewModel.updateTripEndDate($0) }
                ),
                displayedComponents: .date
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("travel.end.date")
                    Text(viewModel.legs.last?.destination.cityName ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .environment(\.timeZone, timezone(for: viewModel.legs.last?.destination ?? fallbackCity))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func legEditor(_ leg: Binding<TravelLeg>) -> some View {
        let legValue = leg.wrappedValue
        let legIndex = viewModel.legs.firstIndex(where: { $0.id == legValue.id }) ?? 0

        return VStack(spacing: 12) {
            HStack {
                Text(String(format: String(localized: "travel.leg.format"), legIndex + 1))
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                Spacer()

                if viewModel.legs.count > 1 {
                    Button {
                        viewModel.removeLeg(legIndex)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red.opacity(0.75))
                    }
                    .accessibilityLabel(String(localized: "travel.remove.leg"))
                }
            }

            HStack(spacing: 10) {
                cityButton(
                    title: String(localized: "travel.origin.city"),
                    city: legValue.origin,
                    action: {
                        selectedLegID = legValue.id
                        selectingOrigin = true
                        showCitySelector = true
                    }
                )

                Button(action: {
                    viewModel.selectLeg(legIndex)
                    viewModel.swapCities()
                }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(.systemGray2))
                        .frame(width: 34, height: 34)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .accessibilityLabel(String(localized: "accessibility.swap.cities"))

                cityButton(
                    title: String(localized: "travel.destination.city"),
                    city: legValue.destination,
                    action: {
                        selectedLegID = legValue.id
                        selectingOrigin = false
                        showCitySelector = true
                    }
                )
            }

            DatePicker(
                selection: Binding(
                    get: { leg.wrappedValue.departureDate },
                    set: { viewModel.updateDeparture($0, legIndex: legIndex) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("travel.departure.label")
                    Text(legValue.origin.cityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .environment(\.timeZone, timezone(for: legValue.origin))

            DatePicker(
                selection: Binding(
                    get: { leg.wrappedValue.arrivalDate },
                    set: { viewModel.updateArrival($0, legIndex: legIndex) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("travel.arrival.label")
                    Text(legValue.destination.cityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .environment(\.timeZone, timezone(for: legValue.destination))
        }
        .padding(12)
        .background(Color(.systemGray6).opacity(0.55))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    viewModel.invalidLegIndex == legIndex
                        ? Color.red.opacity(0.55)
                        : .clear,
                    lineWidth: 1
                )
        )
    }

    private func cityButton(
        title: String,
        city: CitySuggestion,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(city.cityName)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(city.cityEn)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func schedulePicker(
        titleKey: LocalizedStringKey,
        time: TravelScheduleTime,
        onChange: @escaping (Date) -> Void
    ) -> some View {
        DatePicker(
            selection: Binding(
                get: { scheduleDate(time) },
                set: onChange
            ),
            displayedComponents: .hourAndMinute
        ) {
            Text(titleKey)
                .font(.body.weight(.semibold))
        }
        .environment(\.timeZone, .current)
    }

    private func scheduleDate(_ time: TravelScheduleTime) -> Date {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = time.hour
        components.minute = time.minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func timezone(for city: CitySuggestion) -> TimeZone {
        TimeZone(identifier: city.timezoneId) ?? .current
    }

    private var fallbackCity: CitySuggestion {
        CitySuggestion(
            id: TimeZone.current.identifier,
            cityName: "",
            cityEn: "",
            timezoneId: TimeZone.current.identifier,
            continent: ""
        )
    }
}
