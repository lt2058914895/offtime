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
    @State private var isSelectingSource = true
    /// 上次见到的城市数据版本号，用于切回 Tab 时判断是否需要静默刷新
    @State private var lastSeenCitiesRevision: Int = 0
    /// swap 按钮尺寸随 body Dynamic Type 同步缩放，避免图标在大字下撑出固定圆形
    @ScaledMetric(relativeTo: .body) private var swapButtonSize: CGFloat = 44
    
    private var isIPad: Bool { horizontalSizeClass == .regular }
    /// iPhone 横屏（compact vertical）：改走横向布局，充分利用宽度，避免两卡片纵向堆叠
    private var isLandscape: Bool { verticalSizeClass == .compact }
    private var usesHorizontalLayout: Bool { isIPad || isLandscape }
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if usesHorizontalLayout {
                    // iPad 或 iPhone 横屏：源/目标卡片横向并排，充分利用宽度
                    HStack(alignment: .center, spacing: 16) {
                        sourceCard
                        swapButton
                        targetCard
                    }
                    .padding(.horizontal, isIPad ? 24 : 16)
                    .padding(.vertical, 16)
                } else {
                    // iPhone 竖屏：纵向排列
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
            }
            .onChange(of: appEnvironment.citiesRevision) { _, newValue in
                lastSeenCitiesRevision = newValue
                viewModel.loadCities()
            }
            .toast(message: $viewModel.errorMessage)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .citySelector:
                    CitySelectorView(onCitySelected: { city in
                        let model = CityModel(cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId)
                        if isSelectingSource {
                            viewModel.sourceCity = model
                        } else {
                            viewModel.targetCity = model
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
        CardView(isNight: !viewModel.isCityDaytime(viewModel.sourceCity)) {
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
                // 尺寸随 body Dynamic Type 同步缩放，图标与圆形始终保持比例，不再裁切
                .frame(width: swapButtonSize, height: swapButtonSize)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .contentShape(Circle()) // 确保整个圆形区域可点
        }
        // 封顶到 accessibility3：图标按钮视觉无需无限放大，VoiceOver 由 accessibilityLabel 兜底
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .scaleEffect(viewModel.isSwapping ? 0.9 : 1.0)
        .accessibilityLabel(String(localized: "accessibility.swap.cities"))
    }
    
    private var targetCard: some View {
        CardView(isNight: !viewModel.isCityDaytime(viewModel.targetCity)) {
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
                        if let crossDay = viewModel.crossDay {
                            CrossDayBadge(label: crossDay)
                        }
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
                        if let crossDay = viewModel.crossDay {
                            CrossDayBadge(label: crossDay)
                        }
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
                        if !viewModel.timeDifference.isEmpty {
                            Text(viewModel.timeDifference)
                                .font(.body.weight(.semibold))
                                .foregroundColor(Color(.label))
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cityButton(title: String, city: CityModel?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color(.systemGray2))
            
            Button(action: action) {
                HStack {
                    if let city {
                        Text("\(city.cityName) (\(city.cityEn))")
                            .font(.headline)
                            .foregroundColor(Color(.label))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
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
        // amSymbol/pmSymbol 走系统 locale 自动本地化（午前/午後、오전/오후 等）
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
            // 表头：窄横屏 / 大字下标签与「当前时间」按钮放不下时自动回退纵向
            ViewThatFits(in: .horizontal) {
                HStack {
                    datePickerLabel
                    Spacer()
                    currentTimeButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    datePickerLabel
                    currentTimeButton
                }
            }
            
            // 大字 Dynamic Type 或窄屏（横屏 SE 等）放不下并排时，自动回退纵向
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

    /// 日期选择按钮（大字下文字允许缩放避免溢出）
    private var dateButton: some View {
        Button(action: { showDatePicker = true }) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.callout)
                    .foregroundColor(Color(.secondaryLabel))
                Text(ConverterView.sourceDateFormatter.string(from: viewModel.sourceDate))
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
        .accessibilityLabel(String(localized: "converter.select.date") + ": " + ConverterView.sourceDateFormatter.string(from: viewModel.sourceDate))
    }

    /// 时间选择按钮（大字下文字允许缩放避免溢出）
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
}

// MARK: - CardView

private struct CardView<Content: View>: View {
    let content: Content
    let isNight: Bool
    
    init(isNight: Bool = false, @ViewBuilder content: () -> Content) {
        self.isNight = isNight
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(16)
            .background {
                ZStack {
                    Color(.secondarySystemGroupedBackground)
                    if isNight {
                        NightCardBackground()
                    }
                }
            }
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 4)
    }
}

#Preview {
    ConverterView()
}
