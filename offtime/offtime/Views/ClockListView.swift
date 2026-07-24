import SwiftUI

struct ClockListView: View {
    @StateObject private var viewModel = ClockListViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var path = NavigationPath()
    @State private var isShowingDeleteConfirm = false
    @State private var cityToDelete: CityItem?
    @State private var isDragging = false
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                List {
                    ForEach($viewModel.cities) { $city in
                        ClockListCell(
                            city: city,
                            time: viewModel.getLocalTime(city: city),
                            date: viewModel.getLocalDate(city: city),
                            timeDifference: viewModel.getTimeDifference(city: city),
                            isDaytime: viewModel.isDaytime(city: city),
                            onCopy: {
                                let text = viewModel.copyTimeText(city: city)
                                UIPasteboard.general.string = text
                            },
                            onDelete: {
                                cityToDelete = city
                                isShowingDeleteConfirm = true
                            }
                        )
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
                
                if viewModel.cities.isEmpty && viewModel.viewState == .idle {
                    EmptyStateView()
                }
                
                if viewModel.viewState == .loading {
                    LoadingView()
                }
            }
            .navigationTitle("世界时钟")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
                case .aboutPage:
                    AboutPageView()
                case .citySelector:
                    EmptyView()
                }
            }
            .toast(message: $viewModel.errorMessage)
            .onAppear {
                viewModel.loadCities()
            }
            .onChange(of: appEnvironment.settings.use24Hour) { newValue in
                viewModel.use24Hour = newValue
            }
            .alert("确认删除", isPresented: $isShowingDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let city = cityToDelete {
                        viewModel.deleteCity(id: city.id)
                    }
                }
            } message: {
                Text("确定要删除这个城市吗？")
            }
        }
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        viewModel.cities.move(fromOffsets: source, toOffset: destination)
        viewModel.reorderCities(viewModel.cities)
    }
    
    private func delete(at offsets: IndexSet) {
        for offset in offsets {
            let city = viewModel.cities[offset]
            viewModel.deleteCity(id: city.id)
        }
    }
}

struct ClockListCell: View {
    let city: CityItem
    let time: String
    let date: String
    let timeDifference: (offset: String, crossDay: String?)
    let isDaytime: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: isDaytime ? "sun.max" : "moon")
                .foregroundColor(isDaytime ? .yellow : .blue)
                .font(.title)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(city.cityName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(city.cityEn)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(time)
                    .font(.title)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    if let crossDay = timeDifference.crossDay {
                        Text(crossDay)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(timeDifference.offset)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .contextMenu {
            Button("复制时间") {
                onCopy()
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("暂无城市")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("点击右上角添加全球城市")
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
            Text("加载中...")
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
