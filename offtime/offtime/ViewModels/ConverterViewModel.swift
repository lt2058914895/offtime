import Foundation
import Combine
import SwiftData

/// 从会议页跳转转换器时的预填请求：指定源/目标时区与目标时刻（绝对时间）。
struct ConverterPrefill: Equatable, Hashable {
    let id: UUID
    let sourceTimezoneId: String
    let targetTimezoneId: String
    let date: Date?

    init(
        id: UUID = UUID(),
        sourceTimezoneId: String,
        targetTimezoneId: String,
        date: Date?
    ) {
        self.id = id
        self.sourceTimezoneId = sourceTimezoneId
        self.targetTimezoneId = targetTimezoneId
        self.date = date
    }
}

struct ConvertedTimeResult: Identifiable, Equatable {
    let id: UUID
    let cityName: String
    let cityEn: String
    let dateText: String
    let timeText: String
    let endTimeText: String?
    let endDateText: String?
    let durationText: String?
    let differenceText: String
    let crossDayText: String?
}

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published var sourceCity: CityModel?
    @Published var targetCities: [CityModel] = []
    @Published var sourceDate: Date = Date()

    @Published var results: [ConvertedTimeResult] = []
    @Published var durationMinutes: Int = 60
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    @Published var availableCities: [CityModel] = []
    @Published var isSwapping: Bool = false

    private let timezoneService = TimezoneService.shared
    private let cityService: CityService
    private var cancellables = Set<AnyCancellable>()

    init(cityService: CityService? = nil) {
        self.cityService = cityService ?? CityService.shared
        loadCities()

        $sourceCity
            .combineLatest($targetCities, $sourceDate, $durationMinutes)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] inputs in
                let (source, targets, date, duration) = inputs
                self?.convert(
                    source: source,
                    targets: targets,
                    date: date,
                    durationMinutes: duration
                )
            }
            .store(in: &cancellables)

        $use24Hour
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshFormat()
            }
            .store(in: &cancellables)
    }

    func loadCities() {
        do {
            let cities = try cityService.getAllCities()
            availableCities = cities

            if sourceCity == nil && !cities.isEmpty {
                sourceCity = cities.first
            }
            if targetCities.isEmpty && cities.count > 1 {
                targetCities = Array(cities.dropFirst().prefix(3))
            }
        } catch {
            errorMessage = String(localized: "converter.load.cities.failed")
        }
    }

    func refreshFormat() {
        convert(
            source: sourceCity,
            targets: targetCities,
            date: sourceDate,
            durationMinutes: durationMinutes
        )
    }

    func isCityDaytime(_ city: CityModel?) -> Bool {
        guard let city else { return true }
        return timezoneService.isDaytime(timezoneId: city.timezoneId, date: Date())
    }

    private func convert(
        source: CityModel?,
        targets: [CityModel],
        date: Date,
        durationMinutes: Int
    ) {
        guard let source, !targets.isEmpty else {
            results = []
            return
        }

        guard let sourceTimezone = TimeZone(identifier: source.timezoneId) else {
            results = []
            errorMessage = String(localized: "converter.timezone.parse.failed")
            return
        }

        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = sourceTimezone
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )

        guard let absoluteDate = sourceCalendar.date(from: components) else {
            results = []
            errorMessage = String(localized: "converter.convert.failed")
            return
        }

        let endDate = sourceCalendar.date(
            byAdding: .minute,
            value: max(0, durationMinutes),
            to: absoluteDate
        ) ?? absoluteDate

        results = targets.compactMap { target in
            let difference = timezoneService.getTimeDifferenceBetween(
                sourceTimezoneId: source.timezoneId,
                targetTimezoneId: target.timezoneId,
                date: absoluteDate
            )
            let timeText = use24Hour
                ? timezoneService.getLocalTime24(timezoneId: target.timezoneId, date: absoluteDate)
                : timezoneService.getLocalTime12(timezoneId: target.timezoneId, date: absoluteDate)
            let endTimeText = use24Hour
                ? timezoneService.getLocalTime24(timezoneId: target.timezoneId, date: endDate)
                : timezoneService.getLocalTime12(timezoneId: target.timezoneId, date: endDate)
            var targetCalendar = Calendar.current
            targetCalendar.timeZone = TimeZone(identifier: target.timezoneId) ?? .current
            let startDateComponents = targetCalendar.dateComponents([.year, .month, .day], from: absoluteDate)
            let endDateComponents = targetCalendar.dateComponents([.year, .month, .day], from: endDate)
            let crossesMidnight = startDateComponents != endDateComponents
            let endDateText = durationMinutes > 0 && crossesMidnight
                ? timezoneService.getLocalDate(timezoneId: target.timezoneId, date: endDate)
                : nil

            guard let timeText else { return nil }
            return ConvertedTimeResult(
                id: target.id,
                cityName: target.cityName,
                cityEn: target.cityEn,
                dateText: timezoneService.getLocalDate(timezoneId: target.timezoneId, date: absoluteDate) ?? "",
                timeText: timeText,
                endTimeText: durationMinutes > 0 ? endTimeText : nil,
                endDateText: endDateText,
                durationText: durationMinutes > 0
                    ? String(format: String(localized: "meeting.settings.duration.format"), durationMinutes)
                    : nil,
                differenceText: difference.offset,
                crossDayText: difference.crossDay
            )
        }
        viewState = .idle
    }

    /// 应用外部跳转预填（如会议页推荐窗口）：按时区匹配已有城市，找不到时临时构建。
    func applyPrefill(sourceTimezoneId: String, targetTimezoneId: String, date: Date?) {
        let source = findOrMakeCity(timezoneId: sourceTimezoneId)
        let target = findOrMakeCity(timezoneId: targetTimezoneId)
        sourceCity = source
        targetCities = CityIdentity.key(
            cityEn: source.cityEn,
            timezoneId: source.timezoneId
        ) == CityIdentity.key(
            cityEn: target.cityEn,
            timezoneId: target.timezoneId
        ) ? [] : [target]
        if let date {
            sourceDate = date
        }
        refreshFormat()
    }

    private func findOrMakeCity(timezoneId: String) -> CityModel {
        if let match = availableCities.first(where: { $0.timezoneId == timezoneId }) {
            return match
        }
        let (name, en) = CityService.matchCity(for: timezoneId)
        return CityModel(cityName: name, cityEn: en, timezoneId: timezoneId)
    }

    func swapCities() {
        isSwapping = true
        guard let firstTarget = targetCities.first else {
            isSwapping = false
            return
        }

        let oldSource = sourceCity
        sourceCity = firstTarget
        targetCities = [oldSource].compactMap { $0 } + Array(targetCities.dropFirst())
        Haptics.medium()
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.isSwapping = false
            }
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func currentSourceCityDate() -> Date {
        guard let sourceCity,
              let sourceTimezone = TimeZone(identifier: sourceCity.timezoneId) else {
            return Date()
        }
        var sourceCalendar = Calendar.current
        sourceCalendar.timeZone = sourceTimezone
        let components = sourceCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date()
        )
        return Calendar.current.date(from: components) ?? Date()
    }

    func addTarget(_ city: CityModel) {
        let cityKey = CityIdentity.key(cityEn: city.cityEn, timezoneId: city.timezoneId)
        let sourceKey = sourceCity.map {
            CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId)
        }
        guard cityKey != sourceKey,
              !targetCities.contains(where: {
                  CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId) == cityKey
              }) else {
            return
        }
        targetCities.append(city)
    }

    func setSource(_ city: CityModel) {
        let cityKey = CityIdentity.key(cityEn: city.cityEn, timezoneId: city.timezoneId)
        sourceCity = city
        targetCities.removeAll {
            CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId) == cityKey
        }
    }

    func removeTarget(id: UUID) {
        targetCities.removeAll { $0.id == id }
    }

    func addCity(cityName: String, cityEn: String, timezoneId: String, country: String = "") {
        do {
            let exists = try cityService.hasCity(cityEn: cityEn, timezoneId: timezoneId)
            if !exists {
                try cityService.addCity(
                    cityName: cityName,
                    cityEn: cityEn,
                    timezoneId: timezoneId,
                    country: country
                )
            }
            availableCities = try cityService.getAllCities()
            if sourceCity == nil {
                sourceCity = availableCities.first
            }
            if targetCities.isEmpty && availableCities.count > 1 {
                targetCities = Array(availableCities.dropFirst().prefix(3))
            }
        } catch {
            errorMessage = String(localized: "converter.add.city.failed")
        }
    }
}
