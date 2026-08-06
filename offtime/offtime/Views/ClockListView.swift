import SwiftUI

struct ClockListView: View {
    @StateObject private var viewModel = ClockListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path = NavigationPath()
    @State private var isShowingDeleteConfirm = false
    @State private var cityToDelete: CityItem?
    @State private var editMode: EditMode = .inactive
    
    private var isIPad: Bool { horizontalSizeClass == .regular }
    
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
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.cities.isEmpty {
                        Button(editMode == .active ? String(localized: "common.done") : String(localized: "clock.manage")) {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        path.append(AppRoute.cityPicker)
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .cityPicker:
                    CityPickerView(onCitySelected: { city in
                        viewModel.addCity(cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId)
                        path.removeLast()
                    })
                case .privacyPage:
                    PrivacyPageView()
                case .supportPage:
                    SupportPageView()
                case .aboutPage:
                    AboutPageView()
                case .citySelector:
                    EmptyView()
                }
            }
            .toast(message: $viewModel.errorMessage)
            .onChange(of: appEnvironment.settings.use24Hour) { newValue in
                viewModel.use24Hour = newValue
            }
            .onChange(of: viewModel.cities.isEmpty) { isEmpty in
                // 城市全部删除后自动退出编辑模式
                if isEmpty && editMode == .active {
                    withAnimation {
                        editMode = .inactive
                    }
                }
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
        }
    }
    
    // MARK: - iPhone 布局（单列列表）
    private var iphoneLayout: some View {
        List {
            ForEach($viewModel.cities) { $city in
                ClockListCell(
                    city: city,
                    time: viewModel.getLocalTime(city: city),
                    date: viewModel.getLocalDate(city: city),
                    weekday: viewModel.getLocalWeekday(city: city),
                    timeDifference: viewModel.getTimeDifference(city: city),
                    isDaytime: viewModel.isDaytime(city: city),
                    dstStatus: viewModel.getDSTStatus(city: city),
                    onCopy: {
                        let text = viewModel.copyTimeText(city: city)
                        UIPasteboard.general.string = text
                    },
                    onDelete: {
                        cityToDelete = city
                        isShowingDeleteConfirm = true
                    }
                )
            }
            .onMove(perform: move)
            .onDelete(perform: confirmDelete)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
    }
    
    // MARK: - iPad 布局（多列网格）
    private var ipadLayout: some View {
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
                        timeDifference: viewModel.getTimeDifference(city: city),
                        isDaytime: viewModel.isDaytime(city: city),
                        dstStatus: viewModel.getDSTStatus(city: city),
                        onCopy: {
                            let text = viewModel.copyTimeText(city: city)
                            UIPasteboard.general.string = text
                        },
                        onDelete: {
                            cityToDelete = city
                            isShowingDeleteConfirm = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        viewModel.cities.move(fromOffsets: source, toOffset: destination)
        viewModel.reorderCities(viewModel.cities)
    }
    
    /// 编辑模式下滑动删除，先弹出确认弹窗再执行删除
    private func confirmDelete(at offsets: IndexSet) {
        guard let offset = offsets.first else { return }
        cityToDelete = viewModel.cities[offset]
        isShowingDeleteConfirm = true
    }
}

struct ClockListCell: View {
    let city: CityItem
    let time: String
    let date: String
    let weekday: String
    let timeDifference: (offset: String, crossDay: String?)
    let isDaytime: Bool
    let dstStatus: String?
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: isDaytime ? "sun.max" : "moon")
                .foregroundColor(isDaytime ? .yellow : .blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(city.cityName)
                        .font(.body)
                        .fontWeight(.semibold)
                    Text(city.cityEn)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let dstStatus = dstStatus {
                        Text(dstStatus)
                            .font(.caption2)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(dstStatus == String(localized: "clock.dst.summer") ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                            .foregroundColor(dstStatus == String(localized: "clock.dst.summer") ? .orange : .blue)
                            .cornerRadius(3)
                    }
                }
                
                HStack {
                    Text(date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    if !weekday.isEmpty {
                        Text(weekday)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(time)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Spacer()
                    HStack(spacing: 2) {
                        if let crossDay = timeDifference.crossDay {
                            Text(crossDay)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(timeDifference.offset)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(timeDifferenceColor)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .contextMenu {
            Button(String(localized: "clock.copy.time")) {
                onCopy()
            }
            Button(String(localized: "clock.delete.city"), role: .destructive) {
                onDelete()
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
    let city: CityItem
    let time: String
    let date: String
    let weekday: String
    let timeDifference: (offset: String, crossDay: String?)
    let isDaytime: Bool
    let dstStatus: String?
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：城市名 + 日夜图标
            HStack {
                Image(systemName: isDaytime ? "sun.max" : "moon")
                    .foregroundColor(isDaytime ? .yellow : .blue)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(city.cityName)
                            .font(.body)
                            .fontWeight(.semibold)
                        Text(city.cityEn)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let dstStatus = dstStatus {
                        Text(dstStatus)
                            .font(.caption2)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(dstStatus == String(localized: "clock.dst.summer") ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                            .foregroundColor(dstStatus == String(localized: "clock.dst.summer") ? .orange : .blue)
                            .cornerRadius(3)
                    }
                }
                Spacer()
            }
            
            Divider()
            
            // 中部：时间
            Text(time)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            
            // 底部：日期 + 星期 + 时差
            HStack {
                Text(date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !weekday.isEmpty {
                    Text(weekday)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    if let crossDay = timeDifference.crossDay {
                        Text(crossDay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(timeDifference.offset)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(timeDifferenceColor)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .contextMenu {
            Button(String(localized: "clock.copy.time")) { onCopy() }
            Button(String(localized: "clock.delete.city"), role: .destructive) { onDelete() }
        }
    }
    
    private var timeDifferenceColor: Color {
        let offset = timeDifference.offset
        if offset == "0h" { return .secondary }
        return offset.hasPrefix("+") ? .green : .red
    }
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

#Preview {
    ClockListView()
}