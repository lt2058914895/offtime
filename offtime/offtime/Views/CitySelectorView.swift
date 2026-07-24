import SwiftUI

struct CitySelectorView: View {
    @StateObject private var viewModel = CityPickerViewModel()
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    let onCitySelected: (CitySuggestion) -> Void
    
    var body: some View {
        ZStack {
            CitySearchListView(
                viewModel: viewModel,
                searchText: $searchText,
                showAddButton: false,
                onCitySelected: { city in
                    onCitySelected(city)
                    dismiss()
                }
            )
        }
        .navigationTitle("选择城市")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
    }
}

#Preview {
    CitySelectorView(onCitySelected: { _ in })
}