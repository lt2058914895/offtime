import SwiftUI
import SwiftData

struct ClockListView: View {
    @StateObject private var viewModel = ClockListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    /// 当前选中的 Tab（由 MainTabView 传入），用于「仅时钟 Tab 才运行 Timer」
    @Binding var activeTab: AppTab
    @State private var path = NavigationPath()
    @State private var isShowingDeleteConfirm = false
    @State private var cityToDelete: CityModel?
    /// 我们自己的编辑模式开关(单一数据源)。List 的原生 editMode 通过 .constant 只读传入，
    /// 避免 SwiftUI 通过双向绑定回写状态引起渲染循环 / 挂死。
    @State private var isEditing = false
    @State private var isShowingBatchDeleteConfirm = false
    /// 长按城市「分享时间」要分享的文案（非空时弹出 ShareSheet）
    @State private var shareItem: ShareTextItem?
    /// 上次见到的城市数据版本号，用于切回 Tab 时判断是否需要静默刷新
    @State private var lastSeenCitiesRevision: Int = 0

    private var isIPad: Bool { horizontalSizeClass == .regular }

    /// 当前城市时区：作为"本地"时区基准（设置页当前城市选择后全局生效）
    private var localTimezoneId: String {
        appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
    }

    private var localCityName: String? {
        appEnvironment.settings.currentCityName
    }

    /// Timer 只在「App 在前台」且「当前是时钟/会议 Tab」时运行：
    /// 切到设置 Tab 或进后台时暂停，省掉每秒无用的时区重算，防发热省电。
    /// 会议页与时钟页共享同一套「分钟级刷新」，两页各自在 onAppear/onChange 中校正，
    /// 由于两个 Tab 视为同一活跃域，不存在互相启停竞争。
    private var shouldRunTimer: Bool {
        scenePhase == .active && (activeTab == .clock || activeTab == .meeting)
    }

    /// 根据 shouldRunTimer 启停 Timer
    private func updateTimer() {
        if shouldRunTimer {
            appEnvironment.startMinuteClock()
        } else {
            appEnvironment.stopMinuteClock()
        }
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                if isIPad {
                    ipadLayout
                } else {
                    iphoneLayout
                }
                
                if viewModel.cities.isEmpty && viewModel.viewState == .idle {
                    EmptyStateView()
                }
                
                if viewModel.viewState == .loading {
                    LoadingView()
                }
            }
            .navigationTitle(String(localized: "clock.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.cities.isEmpty {
                        Button(isEditing ? String(localized: "common.done") : String(localized: "clock.manage")) {
                            toggleEditMode()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        path.append(AppRoute.cityPicker)
                    }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "accessibility.add.city"))
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .cityPicker:
                    CityPickerView(onCitySelected: { city in
                        viewModel.addCity(cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId, country: city.country)
                        path.removeLast()
                    })
                case .supportPage:
                    SupportPageView()
                case .citySelector:
                    EmptyView()
                case .cityDetail(let cityId):
                    if let city = viewModel.cities.first(where: { $0.id == cityId }) {
                        CityDetailView(city: city)
                    } else {
                        EmptyView()
                    }
                case .reminderList:
                    EmptyView()
                }
            }
            .toast(message: $viewModel.errorMessage)
            .onReceive(appEnvironment.$currentDate) { newValue in
                viewModel.currentDate = newValue
            }
            .onChange(of: appEnvironment.settings.use24Hour) { _, newValue in
                viewModel.use24Hour = newValue
            }
            .onChange(of: viewModel.cities.isEmpty) { _, isEmpty in
                // 城市全部删除后自动退出编辑模式并清空勾选
                if isEmpty && isEditing {
                    withAnimation {
                        isEditing = false
                    }
                    viewModel.clearSelection()
                }
            }
            .onAppear {
                // 兜底：首次显示时按当前状态校正 Timer（onChange 首次不触发）
                updateTimer()
                // 导入等操作会递增 citiesRevision；切回本 Tab 时若发生变化则静默刷新
                if appEnvironment.citiesRevision != lastSeenCitiesRevision {
                    lastSeenCitiesRevision = appEnvironment.citiesRevision
                    viewModel.reloadCitiesSilently()
                }
            }
            .onChange(of: appEnvironment.citiesRevision) { _, newValue in
                lastSeenCitiesRevision = newValue
                viewModel.reloadCitiesSilently()
            }
            .onChange(of: shouldRunTimer) {
                // Timer 仅在「前台 + 时钟 Tab」运行：切到其它 Tab 或进后台时暂停，
                // 回到时钟 Tab 或前台时恢复，详情页复用同一个全局时钟。
                updateTimer()
            }
            .alert(String(localized: "clock.confirm.delete"), isPresented: $isShowingDeleteConfirm) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "common.delete"), role: .destructive) {
                    if let city = cityToDelete {
                        viewModel.deleteCity(id: city.id)
                    }
                }
            } message: {
                Text(String(localized: "clock.confirm.delete.message"))
            }
            .alert(String(localized: "clock.confirm.delete"), isPresented: $isShowingBatchDeleteConfirm) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "common.delete"), role: .destructive) {
                    viewModel.deleteSelectedCities()
                }
            } message: {
                Text(String(localized: "clock.confirm.delete.selected.message") + " (\(viewModel.selectedCityIds.count))")
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(text: item.text)
            }
        }
    }
    
    // MARK: - 管理模式顶部操作栏（全选 / 删除）
    private var editActionBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleSelectAll()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.allSelected ? "checkmark.circle.fill" : "circle")
                    Text(String(localized: "clock.select.all"))
                }
            }
            Spacer()
            Button {
                isShowingBatchDeleteConfirm = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "trash")
                    Text(String(localized: "common.delete"))
                    if !viewModel.selectedCityIds.isEmpty {
                        Text("(\(viewModel.selectedCityIds.count))")
                    }
                }
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(viewModel.selectedCityIds.isEmpty ? .secondary : .red)
            }
            .disabled(viewModel.selectedCityIds.isEmpty)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
    
    // MARK: - 管理模式拖动排序提示（仅 iPhone 列表支持拖动排序，iPad 网格无此能力）
    private var reorderHintBar: some View {
        HStack(spacing: 2) {
            Text(String(localized: "clock.reorder.hint.prefix"))
                .font(.caption2)
            Image(systemName: "line.3.horizontal")
                .font(.caption2.weight(.medium))
            Text(String(localized: "clock.reorder.hint.suffix"))
                .font(.caption2)
        }
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - iPhone 布局（单列列表）
    private var iphoneLayout: some View {
        VStack(spacing: 0) {
            if isEditing {
                editActionBar
                Divider()
                reorderHintBar
            }
            List {
                if isEditing {
                    ForEach(viewModel.cities) { city in
                        clockListCell(city)
                    }
                    .onMove(perform: move)
                } else {
                    ForEach(viewModel.cities) { city in
                        clockListCell(city)
                    }
                }
            }
            .listStyle(.insetGrouped)
            // 只读 .constant：让 List 的 .onMove 手柄照常显示，但禁止 SwiftUI 回写 editMode，
            // 否则会在我们更新选中状态 / 自定义布局时触发渲染循环挂死。
            .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        }
    }

    private func clockListCell(_ city: CityModel) -> some View {
        ClockListCell(
            city: city,
            time: viewModel.getLocalTime(city: city),
            date: viewModel.getLocalDate(city: city),
            weekday: viewModel.getLocalWeekday(city: city),
            timeDifference: viewModel.getTimeDifference(city: city, localTimezoneId: localTimezoneId),
            isDaytime: viewModel.isDaytime(city: city),
            dstStatus: viewModel.getDSTStatus(city: city),
            countryCode: viewModel.countryCode(for: city),
            workingHoursOverlap: viewModel.getWorkingHoursOverlap(city: city, localTimezoneId: localTimezoneId),
            localTimezoneId: localTimezoneId,
            localCityName: localCityName,
            isEditMode: isEditing,
            isSelected: viewModel.selectedCityIds.contains(city.id),
            onToggleSelection: {
                viewModel.toggleSelection(id: city.id)
            },
            onCopy: {
                let text = viewModel.copyTimeText(city: city)
                UIPasteboard.general.string = text
            },
            onShare: {
                shareItem = ShareTextItem(text: viewModel.copyTimeText(city: city))
            },
            onDelete: {
                cityToDelete = city
                isShowingDeleteConfirm = true
            },
            onTap: {
                path.append(AppRoute.cityDetail(city.id))
            }
        )
        .listRowBackground(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - iPad 布局（多列网格）
    private var ipadLayout: some View {
        VStack(spacing: 0) {
            if isEditing {
                editActionBar
                Divider()
            }
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(viewModel.cities) { city in
                       ClockGridCell(
                           city: city,
                           time: viewModel.getLocalTime(city: city),
                           date: viewModel.getLocalDate(city: city),
                           weekday: viewModel.getLocalWeekday(city: city),
                           timeDifference: viewModel.getTimeDifference(city: city, localTimezoneId: localTimezoneId),
                           isDaytime: viewModel.isDaytime(city: city),
                           dstStatus: viewModel.getDSTStatus(city: city),
                            countryCode: viewModel.countryCode(for: city),
                        workingHoursOverlap: viewModel.getWorkingHoursOverlap(city: city, localTimezoneId: localTimezoneId),
                        localTimezoneId: localTimezoneId,
                        localCityName: localCityName,
                        isEditMode: isEditing,
                            isSelected: viewModel.selectedCityIds.contains(city.id),
                            onToggleSelection: {
                                viewModel.toggleSelection(id: city.id)
                            },
                            onCopy: {
                                let text = viewModel.copyTimeText(city: city)
                                UIPasteboard.general.string = text
                            },
                            onShare: {
                                shareItem = ShareTextItem(text: viewModel.copyTimeText(city: city))
                            },
                            onDelete: {
                                cityToDelete = city
                                isShowingDeleteConfirm = true
                            },
                            onTap: {
                                path.append(AppRoute.cityDetail(city.id))
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        viewModel.cities.move(fromOffsets: source, toOffset: destination)
        viewModel.reorderCities(viewModel.cities)
    }
    
    /// 切换管理模式；退出时清空勾选，避免残留选中状态
    private func toggleEditMode() {
        let willBeActive = !isEditing
        withAnimation {
            isEditing = willBeActive
        }
        if !willBeActive {
            viewModel.clearSelection()
        }
    }
}

struct ClockListCell: View {
    let city: CityModel
    let time: String
    let date: String
    let weekday: String
    let timeDifference: (offset: String, crossDay: String?)
    let isDaytime: Bool
    let dstStatus: String?
    let countryCode: String
    let workingHoursOverlap: WorkingHoursOverlap
    let localTimezoneId: String
    let localCityName: String?
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: () -> Void = {}
    let onCopy: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    var onTap: () -> Void = {}

    /// 是否为设置页当前城市（城市名+时区均匹配才标记"本地"）
    private var isLocal: Bool {
        guard let localCityName else { return false }
        return city.timezoneId == localTimezoneId && city.cityName == localCityName
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: isEditMode ? 12 : 16) {
            // 管理模式下的勾选圆圈：空心圆 / 勾选填充（红色提示删除）
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .red : .secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(String(localized: isSelected ? "accessibility.selected" : "accessibility.unselected"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn))
                        .font(.body)
                        .fontWeight(.semibold)
                    if let secondary = CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn) {
                        Text(secondary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if isLocal {
                        Text(String(localized: "meeting.local.badge"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                    if let dstStatus = dstStatus {
                        Text(dstStatus)
                            .font(.caption2)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(3)
                    }
                }

                if !countryCode.isEmpty {
                    HStack(spacing: 6) {
                        Text(flagEmoji(for: countryCode))
                            .font(.system(size: 13))
                        Text(appCountryName(for: countryCode))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(utcText(for: city.timezoneId))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(localized: "clock.time.difference"))
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                        Text(timeDifference.offset)
                            .font(.footnote.weight(.bold))
                            .foregroundColor(timeDifferenceColor)
                            .monospacedDigit()
                    }
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(spacing: 4) {
                        Text(date)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        if !weekday.isEmpty {
                            Text(weekday)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    HStack(alignment: .center, spacing: 5) {
                        if let crossDay = timeDifference.crossDay {
                            CrossDayBadge(label: crossDay)
                        }
                        DayNightTimeBadge(
                            time: time,
                            isDaytime: isDaytime,
                            font: .title3.weight(.semibold)
                        )
                    }
                }
                if !isEditMode {
                    WorkingHoursBar(overlap: workingHoursOverlap, localTimezoneId: localTimezoneId)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode { onToggleSelection() } else { onTap() }
        }
        .contextMenu {
            Button(String(localized: "clock.copy.time")) {
                onCopy()
            }
            Button(String(localized: "clock.share.time")) {
                onShare()
            }
            if isEditMode {
                Button(String(localized: "clock.delete.city"), role: .destructive) {
                    onDelete()
                }
            }
        }
    }

    private var timeDifferenceColor: Color {
        let offset = timeDifference.offset
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }
}

// MARK: - iPad 网格卡片
struct ClockGridCell: View {
    let city: CityModel
    let time: String
    let date: String
    let weekday: String
    let timeDifference: (offset: String, crossDay: String?)
    let isDaytime: Bool
    let dstStatus: String?
    let countryCode: String
    let workingHoursOverlap: WorkingHoursOverlap
    let localTimezoneId: String
    let localCityName: String?
    var isEditMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: () -> Void = {}
    let onCopy: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    var onTap: () -> Void = {}

    /// 是否为设置页当前城市（城市名+时区均匹配才标记"本地"）
    private var isLocal: Bool {
        guard let localCityName else { return false }
        return city.timezoneId == localTimezoneId && city.cityName == localCityName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：城市名 + 国家信息 + 管理模式勾选圆圈
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn))
                            .font(.body)
                            .fontWeight(.semibold)
                        if let secondary = CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn) {
                            Text(secondary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if isLocal {
                            Text(String(localized: "meeting.local.badge"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    if let dstStatus = dstStatus {
                        Text(dstStatus)
                            .font(.caption2)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(3)
                    }
                    if !countryCode.isEmpty {
                        HStack(spacing: 6) {
                            Text(flagEmoji(for: countryCode))
                                .font(.system(size: 13))
                            Text(appCountryName(for: countryCode))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(utcText(for: city.timezoneId))
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Text(String(localized: "clock.time.difference"))
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.secondary)
                        Text(timeDifference.offset)
                            .font(.footnote.weight(.bold))
                            .foregroundColor(timeDifferenceColor)
                            .monospacedDigit()
                        }
                    }
                }
                Spacer()
                if isEditMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .red : .secondary)
                        .accessibilityLabel(String(localized: isSelected ? "accessibility.selected" : "accessibility.unselected"))
                }
            }
            
            Divider()
            
            // 中部：昨日/明日 + 时间 + 昼夜图标
            HStack(alignment: .center, spacing: 8) {
                if let crossDay = timeDifference.crossDay {
                    CrossDayBadge(label: crossDay)
                }
                DayNightTimeBadge(
                    time: time,
                    isDaytime: isDaytime,
                    font: .title2.weight(.bold)
                )
            }
            
            // 底部：日期 + 星期
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(date)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        if !weekday.isEmpty {
                            Text(weekday)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
            }
            if !isEditMode {
                WorkingHoursBar(overlap: workingHoursOverlap, localTimezoneId: localTimezoneId)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode { onToggleSelection() } else { onTap() }
        }
        .contextMenu {
            Button(String(localized: "clock.copy.time")) { onCopy() }
            Button(String(localized: "clock.share.time")) { onShare() }
            if isEditMode {
                Button(String(localized: "clock.delete.city"), role: .destructive) { onDelete() }
            }
        }
    }

    private var timeDifferenceColor: Color {
        let offset = timeDifference.offset
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }
}

/// 用于 `.sheet(item:)` 的分享文案包装（String 非 Identifiable）
struct ShareTextItem: Identifiable {
    let id = UUID()
    let text: String
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text(String(localized: "clock.empty.title"))
                .font(.title)
                .foregroundColor(.secondary)
            
            Text(String(localized: "clock.empty.subtitle"))
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "common.loading"))
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .opacity(0.8)
    }
}

// MARK: - 时钟卡片辅助

/// 国家码 → 国旗 Emoji；非法/空返回 🌐 占位
private func flagEmoji(for countryCode: String) -> String {
    let upper = countryCode.uppercased()
    guard upper.count == 2, upper.allSatisfy({ $0.isASCII && $0.isLetter }) else {
        return "🌐"
    }
    let base: UInt32 = 127397
    return upper.unicodeScalars
        .compactMap { UnicodeScalar(base + $0.value) }
        .reduce(into: "") { result, scalar in
            result.unicodeScalars.append(scalar)
        }
}

/// 当前 App 语言下的国家名
private func appCountryName(for countryCode: String) -> String {
    guard countryCode.count == 2 else { return "" }
    let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
    let locale: Locale
    switch language {
    case "en": locale = Locale(identifier: "en_US")
    default: locale = Locale(identifier: "zh_CN")
    }
    return locale.localizedString(forRegionCode: countryCode) ?? ""
}

struct DayNightTimeBadge: View {
    let time: String
    let isDaytime: Bool
    let font: Font

    var body: some View {
        Text(time)
            .font(font)
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isDaytime
                ? Color(red: 110 / 255.0, green: 168 / 255.0, blue: 220 / 255.0)
                : Color(red: 23 / 255.0, green: 55 / 255.0, blue: 94 / 255.0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(String(localized: isDaytime ? "accessibility.daytime" : "accessibility.nighttime"))
    }
}

/// 时区 ID → UTC 偏移文案，如 UTC+8
private func utcText(for timezoneId: String) -> String {
    guard let timeZone = TimeZone(identifier: timezoneId) else { return "" }
    let seconds = timeZone.secondsFromGMT()
    let hours = seconds / 3600
    let minutes = abs(seconds % 3600) / 60
    if minutes == 0 {
        return String(format: "UTC%+d", hours)
    }
    return String(format: "UTC%+d:%02d", hours, minutes)
}

#Preview {
    ClockListView(activeTab: .constant(.clock))
}
