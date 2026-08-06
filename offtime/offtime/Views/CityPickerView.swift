import SwiftUI

struct CityPickerView: View {
    @StateObject private var viewModel = CityPickerViewModel()
    @State private var searchText = ""
    @State private var toastMessage: String?
    
    let onCitySelected: (CitySuggestion) -> Void
    
    var body: some View {
        ZStack {
            CitySearchListView(
                viewModel: viewModel,
                searchText: $searchText,
                showAddButton: true,
                onCitySelected: { city in
                    selectCity(city)
                }
            )
        }
        .navigationTitle(String(localized: "city.picker.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
        .toast(message: $toastMessage)
    }
    
    private func selectCity(_ city: CitySuggestion) {
        Task {
            let exists = await viewModel.checkCityExists(cityName: city.cityName)
            if exists {
                toastMessage = String(localized: "clock.city.exists")
                return
            }
            
            onCitySelected(city)
        }
    }
}

#Preview {
    CityPickerView(onCitySelected: { _ in })
}