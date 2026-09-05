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
    @ScaledMetric(relativeTo: .body) private var flowIndicatorSize: CGFloat = 44
    private let embedsNavigationStack: Bool
    private let prefill: ConverterPrefill?
    @State private var appliedPrefillID: UUID?

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
                flowIndicator
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

                datePickerRow
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

    private var flowIndicator: some View {
        Image(systemName: "arrow.down")
            .font(.body.weight(.semibold))
            .foregroundColor(Color(.systemGray2))
            .frame(width: flowIndicatorSize, height: flowIndicatorSize)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .accessibilityHidden(true)
    }

    private var targetCard: some View {
        CardView {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 4) {
                    Text(String(localized: "converter.target.city"))
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(.systemGray2))
                    Text("(\(String(localized: "converter.target.hint")))")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    VStack(spacing: 8) {
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
    }

    private func targetResultRow(_ result: ConvertedTimeResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(CityDisplay.primaryName(cityName: result.cityName, cityEn: result.cityEn))
                                .font(.body.weight(.semibold))
                            if let secondary = CityDisplay.secondaryName(cityName: result.cityName, cityEn: result.cityEn) {
                                Text(secondary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let dstText = result.dstText {
                                Text(dstText)
                                    .font(.caption2)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(3)
                            }
                        }

                        HStack(spacing: 6) {
                            Text(result.countryFlag)
                                .font(.system(size: 13))
                            if !result.countryName.isEmpty {
                                Text(result.countryName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(result.utcText)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(localized: "clock.time.difference"))
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                            Text(result.differenceText)
                                .font(.footnote.weight(.bold))
                                .monospacedDigit()
                                .foregroundColor(timeDifferenceColor(result.differenceText))
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        viewModel.removeTarget(id: result.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "converter.remove.target"))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                targetMetadata(result)

                Spacer()

                HStack(alignment: .center, spacing: 5) {
                    DayNightTimeBadge(
                        time: result.timeText,
                        isDaytime: result.isDaytime,
                        font: .title3.weight(.semibold)
                    )
                }
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private func targetMetadata(_ result: ConvertedTimeResult) -> some View {
        Text(result.dateText)
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundColor(.secondary)
        Text(result.weekdayText)
            .font(.subheadline.weight(.bold))
            .foregroundColor(.secondary)
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

    private static let sourceWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
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
            var line = "• \(name) \(result.dateText)"
            if let crossDay = result.crossDayText {
                line += " (\(crossDay))"
            }
            line += " \(result.timeText)"
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
                    .font(.body.weight(.bold))
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
                Text(Self.sourceWeekdayFormatter.string(from: viewModel.sourceDate))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color(.label))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .cornerRadius(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "converter.select.date") + ": "
            + Self.sourceDateFormatter.string(from: viewModel.sourceDate) + " "
            + Self.sourceWeekdayFormatter.string(from: viewModel.sourceDate)
        )
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
