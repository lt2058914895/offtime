import SwiftUI

struct CitySelectorView: View {
    @StateObject private var viewModel = CityPickerViewModel()
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    let onCitySelected: (CitySuggestion) -> Void
    
    var body: some View {
        ZStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索城市", text: $searchText)
                    }
                    .padding(.vertical, 8)
                }
                
                ForEach(viewModel.cityGroups, id: \.name) { group in
                    Section(header: Text(group.name)) {
                        ForEach(group.cities) { city in
                            Button(action: {
                                onCitySelected(city)
                                dismiss()
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
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .listStyle(.grouped)
            
            if viewModel.cityGroups.isEmpty && !searchText.isEmpty {
                noResultsView
            }
            
            if viewModel.viewState == .loading {
                LoadingView()
            }
        }
        .navigationTitle("选择城市")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
    }
    
    private var noResultsView: some View {
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

#Preview {
    CitySelectorView(onCitySelected: { _ in })
}