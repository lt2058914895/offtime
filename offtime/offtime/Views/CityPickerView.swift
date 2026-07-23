import SwiftUI

struct CityPickerView: View {
    @StateObject private var viewModel = CityPickerViewModel()
    @State private var searchText = ""
    @State private var toastMessage: String?
    
    let onCitySelected: (CitySuggestion) -> Void
    
    var body: some View {
        ZStack {
            List {
                // 自定义搜索栏
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
                                selectCity(city)
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
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.accentColor)
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
        .navigationTitle("添加城市")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    dismiss()
                }
            }
        }
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
        .toast(message: $toastMessage)
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
    
    private func selectCity(_ city: CitySuggestion) {
        Task {
            let exists = await viewModel.checkCityExists(timezoneId: city.timezoneId)
            if exists {
                toastMessage = "该城市已存在"
                return
            }
            
            onCitySelected(city)
        }
    }
    
    private func dismiss() {
        if let presentationMode = UIApplication.shared.windows.first?.rootViewController?.presentedViewController {
            presentationMode.dismiss(animated: true)
        }
    }
}

#Preview {
    CityPickerView(onCitySelected: { _ in })
}
