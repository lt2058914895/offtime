import SwiftUI
import SwiftData

struct ConverterView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var path = NavigationPath()
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var showCitySelector = false
    @State private var isSelectingSource = true
    @State private var lastSeenCitiesRevision: Int = 0
    @ScaledMetric(relativeTo: .body) private var swapButtonSize: CGFloat = 44
    private let embedsNavigationStack: Bool
    private let prefill: ConverterPrefill?
    @State private var appliedPrefillID: UUID?

    private let durationOptions = [0, 15, 30, 45, 60, 90, 120]

    init(embedsNavigationStack: Bool = true, prefill: ConverterPrefill? = nil) {
        self.embedsNavigationStack = embedsNavigationStack
        self.prefill = prefill
    }

    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var usesHorizontalLayout: Bool { isIPad || isLandscape }

    var body: some View {
        if embedsNavigationStack {
            NavigationStack(path: $path) {
                converterContent
            }
        } else {
            converterContent
        }
    }

    private var converterContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                sourceCard
                swapButton
                targetCard
            }
            .padding(.horizontal, usesHorizontalLayout && isIPad ? 24 : 16)
            .padding(.vertical, usesHorizontalLayout ? 16 : 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "tab.converter"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: conversionShareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(String(localized: "converter.share.result"))
                .disabled(viewModel.sourceCity == nil || viewModel.results.isEmpty)
            }
        }
        .onChange(of: appEnvironment.settings.use24Hour) { _, newValue in
            viewModel.use24Hour = newValue
        }
        .onAppear {
            viewModel.use24Hour = appEnvironment.settings.use24Hour
            viewModel.refreshFormat()
            if appEnvironment.citiesRevision != lastSeenCitiesRevision {
                lastSeenCitiesRevision = appEnvironment.citiesRevision
                viewModel.loadCities()
            }
            applyPrefillIfNeeded()
        }
        .onChange(of: prefill) { _, _ in
            applyPrefillIfNeeded()
        }
        .onChange(of: appEnvironment.citiesRevision) { _, newValue in
            lastSeenCitiesRevision = newValue
            viewModel.loadCities()
        }
        .toast(message: $viewModel.errorMessage)
    }

    private var sourceCard: some View {
        CardView {
            VStack(spacing: 12) {
                cityButton(
                    title: String(localized: "converter.source.city"),
                    city: viewModel.sourceCity,
                    action: {
                        isSelectingSource = true
                        showCitySelector = true
                    }
                )

                Divider()

                Divider()

                datePickerRow

                Divider()

                durationRow
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    DatePicker(
                        "",
                        selection: $viewModel.sourceDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()

                    Spacer()
                }
                .padding()
                .navigationTitle(String(localized: "converter.select.date"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done")) { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    DatePicker(
                        "",
                        selection: $viewModel.sourceDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                    Spacer()
                }
                .padding()
                .navigationTitle(String(localized: "converter.select.time"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done")) { showTimePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCitySelector) {
            NavigationStack {
                CitySelectorView(onCitySelected: { city in
                    let model = CityModel(
                        cityName: city.cityName,
                        cityEn: city.cityEn,
                        timezoneId: city.timezoneId,
                        country: city.country
                    )
                    if isSelectingSource {
                        viewModel.setSource(model)
                    } else {
                        viewModel.addTarget(model)
                    }
                    showCitySelector = false
                })
            }
        }
    }

    private var durationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.callout)
                .foregroundColor(.secondary)
            Text(String(localized: "converter.duration"))
                .font(.subheadline.weight(.medium))
            Spacer()
            Picker(
                String(localized: "converter.duration"),
                selection: $viewModel.durationMinutes
            ) {
                ForEach(durationOptions, id: \.self) { minutes in
                    Text(String(format: String(localized: "meeting.settings.duration.format"), minutes))
                        .tag(minutes)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var swapButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                viewModel.swapCities()
            }
        }) {
            Image(systemName: usesHorizontalLayout ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(.systemGray2))
                .frame(width: swapButtonSize, height: swapButtonSize)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .contentShape(Circle())
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .scaleEffect(viewModel.isSwapping ? 0.9 : 1.0)
        .accessibilityLabel(String(localized: "accessibility.swap.cities"))
        .disabled(viewModel.targetCities.isEmpty)
        .opacity(viewModel.targetCities.isEmpty ? 0.5 : 1)
    }

    private var targetCard: some View {
        CardView {
            VStack(spacing: 12) {
                HStack {
                    Text(String(localized: "converter.target.city"))
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(.systemGray2))
                    Spacer()
                    Button {
                        isSelectingSource = false
                        showCitySelector = true
                    } label: {
                        Label(String(localized: "converter.add.target"), systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                if viewModel.results.isEmpty {
                    Text(String(localized: "converter.select.city.hint"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(viewModel.results) { result in
                        targetResultRow(result)
                        if result.id != viewModel.results.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func targetResultRow(_ result: ConvertedTimeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(CityDisplay.primaryName(cityName: result.cityName, cityEn: result.cityEn))
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption)
                    Text(result.differenceText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(timeDifferenceColor(result.differenceText))
                }
                Button {
                    viewModel.removeTarget(id: result.id)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel(String(localized: "converter.remove.target"))
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.callout)
                    .foregroundColor(Color(.secondaryLabel))
                Text(result.dateText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let endDateText = result.endDateText {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(endDateText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                if let crossDay = result.crossDayText {
                    CrossDayBadge(label: crossDay)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.callout)
                    .foregroundColor(Color(.secondaryLabel))
                Text(result.timeText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                if let endTime = result.endTimeText {
                    Text("– \(endTime)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer()
                if let duration = result.durationText {
                    Text(duration)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func timeDifferenceColor(_ offset: String) -> Color {
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }

    private func cityButton(title: String, city: CityModel?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color(.systemGray2))

            Button(action: action) {
                HStack(alignment: .center) {
                    if let city {
                        if let secondary = CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn) {
                            Text("\(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn)) (\(secondary))")
                                .font(.headline)
                                .foregroundColor(Color(.label))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn))
                                .font(.headline)
                                .foregroundColor(Color(.label))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(String(localized: "converter.select.city"))
                            .font(.headline)
                            .foregroundColor(Color(.systemGray4))
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(Color(.systemGray4))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
        }
    }

    private static let sourceDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let sourceTimeFormatter24: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let sourceTimeFormatter12: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var sourceTimeFormatter: DateFormatter {
        viewModel.use24Hour ? Self.sourceTimeFormatter24 : Self.sourceTimeFormatter12
    }

    private var conversionShareText: String {
        guard let sourceCity = viewModel.sourceCity else { return "" }
        let sourceName = CityDisplay.primaryName(cityName: sourceCity.cityName, cityEn: sourceCity.cityEn)
        let sourceDate = Self.sourceDateFormatter.string(from: viewModel.sourceDate)
        let sourceTime = sourceTimeFormatter.string(from: viewModel.sourceDate)

        var lines = [String(localized: "converter.share.title")]
        lines.append("\(sourceName) \(sourceDate) \(sourceTime)")

        for result in viewModel.results {
            let name = CityDisplay.primaryName(cityName: result.cityName, cityEn: result.cityEn)
            var line = "• \(name) \(result.dateText) \(result.timeText)"
            if let endTime = result.endTimeText {
                if let endDateText = result.endDateText {
                    line += "–\(endDateText) \(endTime)"
                } else {
                    line += "–\(endTime)"
                }
            }
            if let crossDay = result.crossDayText {
                line += " (\(crossDay))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private var datePickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    datePickerLabel
                    Spacer()
                    currentTimeButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    datePickerLabel
                    currentTimeButton
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    dateButton
                    timeButton
                }
                VStack(spacing: 12) {
                    dateButton
                    timeButton
                }
            }
        }
    }

    private var datePickerLabel: some View {
        Text(String(localized: "converter.datetime"))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(Color(.systemGray3))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var currentTimeButton: some View {
        Button(action: {
            viewModel.sourceDate = viewModel.currentSourceCityDate()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                Text(String(localized: "converter.current.time"))
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.accentColor)
        }
    }

    private var dateButton: some View {
        Button(action: { showDatePicker = true }) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.callout)
                    .foregroundColor(Color(.secondaryLabel))
                Text(Self.sourceDateFormatter.string(from: viewModel.sourceDate))
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "converter.select.date") + ": " + Self.sourceDateFormatter.string(from: viewModel.sourceDate))
    }

    private var timeButton: some View {
        Button(action: { showTimePicker = true }) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.callout)
                    .foregroundColor(Color(.secondaryLabel))
                Text(sourceTimeFormatter.string(from: viewModel.sourceDate))
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "converter.select.time") + ": " + sourceTimeFormatter.string(from: viewModel.sourceDate))
    }

    private func applyPrefillIfNeeded() {
        guard let prefill, appliedPrefillID != prefill.id else { return }
        appliedPrefillID = prefill.id
        viewModel.applyPrefill(
            sourceTimezoneId: prefill.sourceTimezoneId,
            targetTimezoneId: prefill.targetTimezoneId,
            date: prefill.date
        )
    }
}

private struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 4)
    }
}

#Preview {
    ConverterView()
}
