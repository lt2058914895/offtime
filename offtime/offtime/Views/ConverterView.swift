import SwiftUI

struct ConverterView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @State private var path = NavigationPath()
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var isSelectingSource = true
    
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    sourceCard
                    
                    swapButton
                    
                    targetCard
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
                case .citySelector:
                    CitySelectorView(onCitySelected: { city in
                        let item = CityItem(id: UUID(), cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId, sortIndex: 0, isTop: false)
                        if isSelectingSource {
                            viewModel.sourceCity = item
                        } else {
                            viewModel.targetCity = item
                        }
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
                    isSelectingSource = true
                    path.append(AppRoute.citySelector)
                })
                
                Divider()
                
                datePickerRow
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    DatePicker(
                        "",
                        selection: $viewModel.sourceDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    DatePicker(
                        "",
                        selection: $viewModel.sourceDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("选择时间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showTimePicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    private var swapButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                viewModel.swapCities()
            }
        }) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(.systemGray2))
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
        .scaleEffect(viewModel.isSwapping ? 0.9 : 1.0)
    }
    
    private var targetCard: some View {
        CardView {
            VStack(spacing: 12) {
                cityButton(title: "目标城市", city: viewModel.targetCity, action: {
                    isSelectingSource = false
                    path.append(AppRoute.citySelector)
                })
                
                Divider()
                
                resultDateTimeRow
            }
        }
    }
    
    private var resultDateTimeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日期时间")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(Color(.systemGray3))
            
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.callout)
                        .foregroundColor(Color(.secondaryLabel))
                    Text(viewModel.resultDate)
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(.label))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.callout)
                        .foregroundColor(Color(.secondaryLabel))
                    Text(viewModel.resultTime)
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color(.label))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.callout)
                        .foregroundColor(Color(.secondaryLabel))
                    if let crossDay = viewModel.crossDay {
                        Text(crossDay)
                            .font(.body.weight(.semibold))
                            .foregroundColor(crossDay == "明日" ? Color.orange : Color.blue)
                    }
                    if !viewModel.timeDifference.isEmpty {
                        Text(viewModel.timeDifference)
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                }
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
        }
    }
    
    private var sourceDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
    
    private var sourceTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    private var datePickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日期时间")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(.systemGray3))
                
                Spacer()
                
                Button(action: {
                    viewModel.sourceDate = viewModel.currentSourceCityDate()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                        Text("当前时间")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
            }
            
            HStack(spacing: 12) {
                Button(action: { showDatePicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(sourceDateFormatter.string(from: viewModel.sourceDate))
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                
                Button(action: { showTimePicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.callout)
                            .foregroundColor(Color(.secondaryLabel))
                        Text(sourceTimeFormatter.string(from: viewModel.sourceDate))
                            .font(.body.weight(.semibold))
                            .foregroundColor(Color(.label))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
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
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.03), radius: 4)
    }
}

#Preview {
    ConverterView()
}
