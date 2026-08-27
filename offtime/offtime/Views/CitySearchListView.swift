import SwiftUI

/// 城市搜索列表的共享组件，供 CityPickerView 和 CitySelectorView 复用
struct CitySearchListView: View {
    @ObservedObject var viewModel: CityPickerViewModel
    @Binding var searchText: String
    let showAddButton: Bool
    let onCitySelected: (CitySuggestion) -> Void

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                List {
                    searchSection

                    if viewModel.isSearching {
                        searchContent
                    } else {
                        browseContent
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
                .overlay(alignment: .trailing) {
                    if !viewModel.isSearching && viewModel.viewState == .idle {
                        indexBar { code in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(code, anchor: .top)
                            }
                        }
                    }
                }
            }

            if viewModel.viewState == .loading {
                LoadingView()
            }
        }
    }

    // MARK: - 浏览（按国家分组）

    @ViewBuilder
    private var browseContent: some View {
        ForEach(viewModel.cityGroups) { group in
            Section(header: groupHeader(group)) {
                ForEach(group.cities) { city in
                    cityRow(city, countryName: nil)
                }
            }
            .id(group.code)
        }
    }

    // MARK: - 搜索（扁平结果）

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.selectedCountry != nil {
            ForEach(viewModel.selectedCountryCities) { city in
                cityRow(city, countryName: nil)
            }
        } else if viewModel.searchResults.isEmpty && viewModel.matchedCountries.isEmpty {
            noResultsSection
        } else {
            if !viewModel.matchedCountries.isEmpty {
                countryResultsSection
            }
            if !viewModel.searchResults.isEmpty {
                Section {
                    Text(String(format: String(localized: "city.search.count"), viewModel.searchResults.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(viewModel.searchResults) { result in
                    cityRow(result.city, countryName: result.countryName)
                }
            }
        }
    }

    // MARK: - 国家匹配结果

    private var countryResultsSection: some View {
        Section {
            ForEach(viewModel.matchedCountries) { match in
                Button {
                    viewModel.selectCountry(match)
                } label: {
                    HStack(spacing: 12) {
                        Text(flagEmoji(for: match.code))
                            .font(.system(size: 26))
                            .frame(width: 36)
                        Text(match.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text("\(match.cities.count)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(.systemGray3))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            }
        } header: {
            Text(String(localized: "city.search.country"))
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(nil)
        }
    }

    // MARK: - 字母索引条

    private func indexBar(onSelect: @escaping (String) -> Void) -> some View {
        let letters = ["★"] + viewModel.indexLetters
        return VStack(spacing: 2) {
            ForEach(letters, id: \.self) { letter in
                Button {
                    let target = letter == "★"
                        ? viewModel.cityGroups.first?.code
                        : viewModel.cityGroups.first(where: { $0.indexLetter == letter })?.code
                    if let target {
                        onSelect(target)
                    }
                } label: {
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 15)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.trailing, 2)
        .accessibilityLabel(String(localized: "city.search.index"))
    }

    // MARK: - 分组头

    private func groupHeader(_ group: CountryGroup) -> some View {
        HStack(spacing: 6) {
            if let icon = groupIcon(for: group.code) {
                Text(icon)
            }
            Text(group.name)
            Text("\(group.cities.count)")
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color(.systemGray5))
                .clipShape(Capsule())
        }
        .font(.footnote.weight(.semibold))
        .foregroundColor(.secondary)
        .textCase(nil)
    }

    /// 分组头图标：热门无图标，极地分组用主题图标，国家分组用国旗
    private func groupIcon(for code: String) -> String? {
        switch code {
        case "hot": return nil
        case "arctic": return "❄️"
        case "antarctica": return "🐧"
        default: return flagEmoji(for: code)
        }
    }

    // MARK: - 城市行

    private func cityRow(_ city: CitySuggestion, countryName: String?) -> some View {
        let isAdded = showAddButton
            && viewModel.addedCityKeys.contains(
                CityIdentity.key(cityEn: city.cityEn, timezoneId: city.timezoneId)
            )

        return Button(action: {
            onCitySelected(city)
        }) {
            HStack(spacing: 12) {
                Text(flagEmoji(for: city.country))
                    .font(.system(size: 26))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(city.cityName)
                            .font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        dstBadge(dstStatus(for: city.timezoneId))
                    }
                    Text(subtitle(for: city, countryName: countryName))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(utcOffsetText(for: city.timezoneId))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                if showAddButton {
                    if isAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.accentColor))
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isAdded ? 0.7 : 1)
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .accessibilityHint(showAddButton ? String(localized: "city.hint.add") : String(localized: "city.hint.select"))
    }

    /// 副标题：搜索时附加国家名，避免同名城市混淆
    private func subtitle(for city: CitySuggestion, countryName: String?) -> String {
        guard let countryName, !countryName.isEmpty else {
            return city.cityEn
        }
        return "\(city.cityEn) · \(countryName)"
    }

    // MARK: - 搜索栏

    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField(String(localized: "city.search.placeholder"), text: $searchText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(String(localized: "city.search.placeholder"))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(String(localized: "common.clear"))
                }
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - 无结果

    private var noResultsSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color(.systemGray4)))
                Text(String(localized: "city.no.results"))
                    .font(.headline)
                Text(String(localized: "city.try.different"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .multilineTextAlignment(.center)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 时区偏移

    private func utcOffsetText(for timezoneId: String) -> String {
        guard let timeZone = TimeZone(identifier: timezoneId) else { return "" }
        let seconds = timeZone.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs(seconds % 3600) / 60
        if minutes == 0 {
            return String(format: "UTC%+d", hours)
        }
        return String(format: "UTC%+d:%02d", hours, minutes)
    }

    // MARK: - 夏令时/冬令时标签

    private func dstStatus(for timezoneId: String) -> String? {
        TimezoneService.shared.getDSTStatus(timezoneId: timezoneId)
    }

    /// 夏令时/冬令时胶囊标签（样式与时钟列表卡片一致）
    @ViewBuilder
    private func dstBadge(_ status: String?) -> some View {
        if let status {
            Text(status)
                .font(.caption2)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(status == String(localized: "clock.dst.summer") ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(status == String(localized: "clock.dst.summer") ? .orange : .blue)
                .cornerRadius(3)
        }
    }

    // MARK: - 国旗 Emoji

    private func flagEmoji(for countryCode: String) -> String {
        let base: UInt32 = 127397
        return countryCode
            .uppercased()
            .unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .reduce(into: "") { result, scalar in
                result.unicodeScalars.append(scalar)
            }
    }
}
