import SwiftUI

/// 城市搜索列表的共享组件，供 CityPickerView 和 CitySelectorView 复用
struct CitySearchListView: View {
    @ObservedObject var viewModel: CityPickerViewModel
    @Binding var searchText: String
    let showAddButton: Bool
    let onCitySelected: (CitySuggestion) -> Void
    
    var body: some View {
        List {
            // 搜索栏
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索城市", text: $searchText)
                }
                .padding(.vertical, 8)
            }
            
            // 城市分组列表
            ForEach(viewModel.cityGroups, id: \.name) { group in
                Section(header: Text(group.name)) {
                    ForEach(group.cities) { city in
                        Button(action: {
                            onCitySelected(city)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.cityName)
                                        .font(.body)
                                    Text(city.cityEn)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if showAddButton {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .listStyle(.grouped)
        
        // 无结果视图
        if viewModel.cityGroups.isEmpty && !searchText.isEmpty {
            CitySearchNoResultsView()
        }
        
        // 加载中视图
        if viewModel.viewState == .loading {
            LoadingView()
        }
    }
}

/// 无搜索结果视图
struct CitySearchNoResultsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("未找到城市")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("请更换关键词")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}