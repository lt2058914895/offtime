import SwiftUI

struct ConverterView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @State private var path = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    sourceCard
                    
                    swapButton
                    
                    targetCard
                    
                    resultCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("时区转换器")
            .navigationBarTitleDisplayMode(.large)
            .toast(message: $viewModel.errorMessage)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .cityPicker:
                    CityPickerView(onCitySelected: { city in
                        viewModel.addCity(cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId)
                        path.removeLast()
                    })
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private var sourceCard: some View {
        CardView {
            VStack(spacing: 12) {
                cityButton(title: "起点城市", city: viewModel.sourceCity, action: {
                    path.append(AppRoute.cityPicker)
                })
                
                Divider()
                
                datePickerRow
            }
        }
    }
    
    private var swapButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                viewModel.swapCities()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 4)
                
                Image(systemName: "arrow.up.down")
                    .font(.title2)
                    .foregroundColor(Color(.systemGray4))
            }
            .frame(width: 44, height: 44)
        }
        .scaleEffect(viewModel.isSwapping ? 0.95 : 1.0)
    }
    
    private var targetCard: some View {
        CardView {
            cityButton(title: "目标城市", city: viewModel.targetCity, action: {
                path.append(AppRoute.cityPicker)
            })
        }
    }
    
    private var resultCard: some View {
        CardView {
            VStack(spacing: 12) {
                Text("转换结果")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(.systemGray5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 6) {
                    Text(viewModel.resultTime)
                        .font(.system(size: 44))
                        .fontWeight(.bold)
                    
                    if !viewModel.resultDate.isEmpty {
                        Text(viewModel.resultDate)
                            .font(.body)
                            .foregroundColor(Color(.systemGray4))
                    }
                    
                    HStack(spacing: 8) {
                        if let crossDay = viewModel.crossDay {
                            Text(crossDay)
                                .font(.body)
                                .foregroundColor(Color(.systemGray4))
                        }
                        
                        if !viewModel.timeDifference.isEmpty {
                            Text(viewModel.timeDifference)
                                .font(.body)
                                .foregroundColor(Color(.systemGray4))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func cityButton(title: String, city: CityItem?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color(.systemGray5))
            
            Button(action: action) {
                HStack {
                    Text(city != nil ? "\(city!.cityName) (\(city!.cityEn))" : "选择城市")
                        .font(.headline)
                        .foregroundColor(city != nil ? Color(.label) : Color(.systemGray4))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(Color(.systemGray4))
                }
            }
        }
    }
    
    private var datePickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日期时间")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color(.systemGray5))
            
            DatePicker(
                "",
                selection: $viewModel.sourceDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
        }
    }
}

// MARK: - CardView

private struct CardView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 4)
    }
}

#Preview {
    ConverterView()
}
