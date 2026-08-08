import SwiftUI

struct ConverterView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path = NavigationPath()
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var isSelectingSource = true
    
    private var isIPad: Bool { horizontalSizeClass == .regular }
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if isIPad {
                    // iPad：源/目标卡片横向并排
                    HStack(alignment: .center, spacing: 16) {
                        sourceCard
                        swapButton
                        targetCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                } else {
                    // iPhone：纵向排列
                    VStack(spacing: 16) {
                        sourceCard
                        swapButton
                        targetCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "converter.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: conversionShareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(String(localized: "converter.share.result"))
                    .disabled(viewModel.sourceCity == nil || viewModel.targetCity == nil)
                }
            }
            .onChange(of: appEnvironment.settings.use24Hour) { newValue in
                viewModel.use24Hour = newValue
            }
            .onAppear {
                viewModel.use24Hour = appEnvironment.settings.use24Hour
                viewModel.refreshFormat()
            }
            .toast(message: $viewModel.errorMessage)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .citySelector:
                    CitySelectorView(onCitySelected: { city in
                        let item = CityItem(id: UUID(), cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId, sortIndex: 0, isTop: false)
                        if isSelectingSource {
                            viewModel.sourceCity = item
                        } else {
                            viewModel.targetCity = item
                        }
                        path.removeLast()
                    })
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private var sourceCard: some View {
        CardView {
            VStack(spacing: 12) {
                cityButton(title: String(localized: "converter.source.city"), city: viewModel.sourceCity, action: {
                    isSelectingSource = true
                    path.append(AppRoute.citySelector)
                })
                
                Divider()
                
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
            .presentationDetents([.medium])
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
            .presentationDetents([.medium])
        }
    }
    
    private var swapButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                viewModel.swapCities()
            }
        }) {
            Image(systemName: isIPad ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(.systemGray2))
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .scaleEffect(viewModel.isSwapping ? 0.9 : 1.0)
        .accessibilityLabel(String(localized: "accessibility.swap.cities"))
    }
    
    private var targetCard: some View {
        CardView {
            VStack(spacing: 12) {
                cityButton(title: String(localized: "converter.target.city"), city: viewModel.targetCity, action: {
                    isSelectingSource = false
                    path.append(AppRoute.citySelector)
                })
                
                Divider()
                
                resultDateTimeRow
            }
        }
    }
    
    private var resultDateTimeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "converter.datetime"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Color(.systemGray3))
            
            // 大字 Dynamic Type 下 HStack 放不下时自动回退 VStack，避免溢出
            ViewThatFits(in: .horizontal) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(viewModel.resultDate)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(viewModel.resultTime)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        if let crossDay = viewModel.crossDay {
                            Text(crossDay)
                                .font(.body.weight(.semibold))
                                .foregroundColor(crossDay == String(localized: "clock.tomorrow") ? Color.orange : Color.blue)
                        }
                        if !viewModel.timeDifference.isEmpty {
                            Text(viewModel.timeDifference)
                                .font(.body.weight(.semibold))
                                .foregroundColor(Color(.label))
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(viewModel.resultDate)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(viewModel.resultTime)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        if let crossDay = viewModel.crossDay {
                            Text(crossDay)
                                .font(.body.weight(.semibold))
                                .foregroundColor(crossDay == String(localized: "clock.tomorrow") ? Color.orange : Color.blue)
                        }
                        if !viewModel.timeDifference.isEmpty {
                            Text(viewModel.timeDifference)
                                .font(.body.weight(.semibold))
                                .foregroundColor(Color(.label))
                        }
                    }
                }
            }
        }
    }
    
    private func cityButton(title: String, city: CityItem?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color(.systemGray5))
            
            Button(action: action) {
                HStack {
                    if let city {
                        Text("\(city.cityName) (\(city.cityEn))")
                            .font(.headline)
                            .foregroundColor(Color(.label))
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
        formatter.dateFormat = "yyyy-MM-dd"
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
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()
    
    private var sourceTimeFormatter: DateFormatter {
        viewModel.use24Hour ? Self.sourceTimeFormatter24 : Self.sourceTimeFormatter12
    }
    
    /// 分享文案：「源城市 源日期 源时间 = 目标城市 目标日期 目标时间」
    private var conversionShareText: String {
        let srcName = viewModel.sourceCity?.cityName ?? ""
        let srcDate = Self.sourceDateFormatter.string(from: viewModel.sourceDate)
        let srcTime = sourceTimeFormatter.string(from: viewModel.sourceDate)
        let tgtName = viewModel.targetCity?.cityName ?? ""
        return "\(srcName) \(srcDate) \(srcTime) = \(tgtName) \(viewModel.resultDate) \(viewModel.resultTime)"
    }
    
    private var datePickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "converter.datetime"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(.systemGray3))
                
                Spacer()
                
                Button(action: {
                    viewModel.sourceDate = viewModel.currentSourceCityDate()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                        Text(String(localized: "converter.current.time"))
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: { showDatePicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(ConverterView.sourceDateFormatter.string(from: viewModel.sourceDate))
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "converter.select.date") + ": " + ConverterView.sourceDateFormatter.string(from: viewModel.sourceDate))
                
                Button(action: { showTimePicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(sourceTimeFormatter.string(from: viewModel.sourceDate))
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
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
        }
    }
}

// MARK: - CardView

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
