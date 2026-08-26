import SwiftUI

struct CityPickerView: View {
    @StateObject private var viewModel = CityPickerViewModel()
    @State private var searchText = ""
    @State private var toastMessage: String?
    @Environment(\.dismiss) private var dismiss
    
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
        .toast(message: $toastMessage)
    }
    
    private func selectCity(_ city: CitySuggestion) {
        Task {
            let exists = await viewModel.checkCityExists(cityEn: city.cityEn, timezoneId: city.timezoneId)
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
