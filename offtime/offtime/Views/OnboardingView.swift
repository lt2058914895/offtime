import SwiftUI
import Combine

/// 首次启动引导：3 步（欢迎 → 添加城市 → 功能介绍）
struct OnboardingView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            welcomeStep.tag(0)
            addCitiesStep.tag(1)
            featuresStep.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color(.systemBackground))
        .overlay(alignment: .topTrailing) {
            if page < 2 {
                Button(String(localized: "onboarding.skip")) {
                    appEnvironment.completeOnboarding()
                }
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.trailing, 20)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Step 1: 欢迎

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            Text(String(localized: "onboarding.welcome.title"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text(String(localized: "onboarding.welcome.subtitle"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            nextButton
        }
        .padding(.horizontal)
        .padding(.bottom, 56)
    }

    // MARK: - Step 2: 添加城市

    private var addCitiesStep: some View {
        VStack(spacing: 20) {
            Text(String(localized: "onboarding.cities.title"))
                .font(.title)
                .fontWeight(.bold)
            Text(String(localized: "onboarding.cities.subtitle"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ForEach(viewModel.quickCities) { city in
                    Button { viewModel.toggle(city) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CityDisplay.primaryName(cityName: city.cityName, cityEn: city.cityEn)).font(.body).fontWeight(.medium)
                                if let secondary = CityDisplay.secondaryName(cityName: city.cityName, cityEn: city.cityEn) {
                                    Text(secondary).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: viewModel.isAdded(city) ? "checkmark.circle.fill" : "plus.circle")
                                .font(.title3)
                                .foregroundColor(viewModel.isAdded(city) ? .green : .accentColor)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Spacer()
            nextButton
        }
        .padding(.horizontal)
        .padding(.top, 40)
        .padding(.bottom, 56)
    }

    // MARK: - Step 3: 功能介绍

    private var featuresStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(String(localized: "onboarding.features.title"))
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 18) {
                featureRow(icon: "arrow.up.arrow.down",
                           title: "onboarding.features.manage",
                           desc: "onboarding.features.manage.desc")
                featureRow(icon: "person.2",
                           title: "onboarding.features.meeting",
                           desc: "onboarding.features.meeting.desc")
                featureRow(icon: "repeat",
                           title: "onboarding.features.converter",
                           desc: "onboarding.features.converter.desc")
                featureRow(icon: "clock",
                           title: "onboarding.features.format",
                           desc: "onboarding.features.format.desc")
                featureRow(icon: "moon",
                           title: "onboarding.features.theme",
                           desc: "onboarding.features.theme.desc")
            }
            .padding(.horizontal, 28)

            Spacer()

            Button {
                appEnvironment.completeOnboarding()
            } label: {
                Text(String(localized: "onboarding.start"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .accessibilityIdentifier("onboarding.start")
            .padding(.horizontal)
        }
        .padding(.horizontal)
        .padding(.bottom, 56)
    }

    private func featureRow(icon: String, title: LocalizedStringKey, desc: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var nextButton: some View {
        Button {
            withAnimation { page += 1 }
        } label: {
            Text(String(localized: "onboarding.next"))
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accentColor)
                .cornerRadius(12)
        }
        .padding(.horizontal)
    }
}

/// 引导页第 2 步的快捷添加城市状态
@MainActor
private final class OnboardingViewModel: ObservableObject {
    @Published var addedCityNames: Set<String> = []

    struct QuickCity: Identifiable {
        let id: String
        let cityName: String
        let cityEn: String
        let timezoneId: String
        let country: String
    }

    /// 几个高频国际城市，供用户一键添加（名称/时区与 cities.json 保持一致）
    let quickCities: [QuickCity] = [
        QuickCity(id: "America/New_York", cityName: "纽约", cityEn: "New York", timezoneId: "America/New_York", country: "US"),
        QuickCity(id: "Europe/London", cityName: "伦敦", cityEn: "London", timezoneId: "Europe/London", country: "GB"),
        QuickCity(id: "Asia/Tokyo", cityName: "东京", cityEn: "Tokyo", timezoneId: "Asia/Tokyo", country: "JP"),
        QuickCity(id: "Europe/Paris", cityName: "巴黎", cityEn: "Paris", timezoneId: "Europe/Paris", country: "FR"),
    ]

    private let cityService = CityService.shared

    init() {
        if let cities = try? cityService.getAllCities() {
            addedCityNames = Set(cities.map { $0.cityName })
        }
    }

    func isAdded(_ city: QuickCity) -> Bool {
        addedCityNames.contains(city.cityName)
    }

    func toggle(_ city: QuickCity) {
        if isAdded(city) {
            if let existing = (try? cityService.getAllCities())?.first(where: { $0.cityName == city.cityName }) {
                do {
                    try cityService.deleteCity(id: existing.id)
                    addedCityNames.remove(city.cityName)
                } catch {
                    // 删除失败时保持 UI 与 DB 一致（仍显示已添加）
                }
            }
        } else {
            do {
                try cityService.addCity(cityName: city.cityName, cityEn: city.cityEn, timezoneId: city.timezoneId, country: city.country)
                addedCityNames.insert(city.cityName)
            } catch {
                // 添加失败（如重复）时不更新 UI，避免状态与 DB 不一致
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppEnvironment())
}
