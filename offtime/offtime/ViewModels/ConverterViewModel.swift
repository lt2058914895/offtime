import Foundation
import Combine
import SwiftData

struct ConverterCitySnapshot: Codable, Equatable {
    let cityName: String
    let cityEn: String
    let timezoneId: String
    let country: String

    init(city: CityModel) {
        cityName = city.cityName
        cityEn = city.cityEn
        timezoneId = city.timezoneId
        country = city.country
    }
}

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
    let countryFlag: String
    let countryName: String
    let utcText: String
    let dstText: String?
    let isDaytime: Bool
    let dateText: String
    let weekdayText: String
    let timeText: String
    let differenceText: String
    let crossDayText: String?
}

@MainActor
final class ConverterViewModel: ObservableObject {
    @Published var sourceCity: CityModel?
    @Published var targetCities: [CityModel] = []
    @Published var sourceDate: Date = Date()

    @Published var results: [ConvertedTimeResult] = []
    @Published var viewState: ViewState = .idle
    @Published var errorMessage: String?
    @Published var use24Hour: Bool = AppSettings.defaults.use24Hour
    @Published var availableCities: [CityModel] = []

    private let timezoneService = TimezoneService.shared
    private let cityService: CityService
    private var cancellables = Set<AnyCancellable>()
    private static let sourceSnapshotKey = "converter_source_city_snapshot"
    private static let targetSnapshotsKey = "converter_target_city_snapshots"

    init(cityService: CityService? = nil) {
        self.cityService = cityService ?? CityService.shared
        loadCities()

        $sourceCity
            .combineLatest($targetCities, $sourceDate)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] inputs in
                let (source, targets, date) = inputs
                self?.convert(
                    source: source,
                    targets: targets,
                    date: date
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
        } catch {
            errorMessage = String(localized: "converter.load.cities.failed")
        }
    }

    /// 仅在用户从未选择过起点时使用设置页当前城市；已保存的选择不受时钟列表影响。
    func applyDefaultSource(currentCity: CityModel?) {
        guard sourceCity == nil,
              UserDefaults.standard.object(forKey: Self.sourceSnapshotKey) == nil else {
            return
        }
        sourceCity = currentCity
    }

    private func makeCity(from snapshot: ConverterCitySnapshot) -> CityModel {
        if let match = availableCities.first(where: {
            CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId)
                == CityIdentity.key(cityEn: snapshot.cityEn, timezoneId: snapshot.timezoneId)
        }) {
            return match
        }
        return CityModel(
            cityName: snapshot.cityName,
            cityEn: snapshot.cityEn,
            timezoneId: snapshot.timezoneId,
            country: snapshot.country
        )
    }

    func restoreSavedCities(currentCity: CityModel?) {
        loadCities()

        if let data = UserDefaults.standard.data(forKey: Self.sourceSnapshotKey),
           let snapshot = try? JSONDecoder().decode(ConverterCitySnapshot.self, from: data) {
            sourceCity = makeCity(from: snapshot)
        } else {
            sourceCity = currentCity
        }

        if let data = UserDefaults.standard.data(forKey: Self.targetSnapshotsKey),
           let snapshots = try? JSONDecoder().decode([ConverterCitySnapshot].self, from: data) {
            targetCities = snapshots.map(makeCity(from:))
        } else {
            targetCities = []
        }
    }

    private func saveSourceSnapshot() {
        guard let sourceCity else {
            UserDefaults.standard.removeObject(forKey: Self.sourceSnapshotKey)
            return
        }
        if let data = try? JSONEncoder().encode(ConverterCitySnapshot(city: sourceCity)) {
            UserDefaults.standard.set(data, forKey: Self.sourceSnapshotKey)
        }
    }

    private func saveTargetSnapshots() {
        let snapshots = targetCities.map(ConverterCitySnapshot.init)
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: Self.targetSnapshotsKey)
        }
    }

    func refreshFormat() {
        convert(
            source: sourceCity,
            targets: targetCities,
            date: sourceDate
        )
    }

    func isCityDaytime(_ city: CityModel?) -> Bool {
        guard let city else { return true }
        return timezoneService.isDaytime(timezoneId: city.timezoneId, date: Date())
    }

    private func convert(
        source: CityModel?,
        targets: [CityModel],
        date: Date
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

        results = targets.compactMap { target in
            let difference = timezoneService.getTimeDifferenceBetween(
                sourceTimezoneId: source.timezoneId,
                targetTimezoneId: target.timezoneId,
                date: absoluteDate
            )
            let timeText = use24Hour
                ? timezoneService.getLocalTime24(timezoneId: target.timezoneId, date: absoluteDate)
                : timezoneService.getLocalTime12(timezoneId: target.timezoneId, date: absoluteDate)
            guard let timeText else { return nil }
            return ConvertedTimeResult(
                id: target.id,
                cityName: target.cityName,
                cityEn: target.cityEn,
                countryFlag: CountryDisplay.flagEmoji(for: target.country),
                countryName: CountryDisplay.name(for: target.country),
                utcText: timezoneService.getUTCText(timezoneId: target.timezoneId) ?? "",
                dstText: timezoneService.getDSTStatus(timezoneId: target.timezoneId, date: absoluteDate),
                isDaytime: timezoneService.isDaytime(timezoneId: target.timezoneId, date: absoluteDate),
                dateText: timezoneService.getLocalDate(timezoneId: target.timezoneId, date: absoluteDate) ?? "",
                weekdayText: timezoneService.getLocalWeekday(timezoneId: target.timezoneId, date: absoluteDate) ?? "",
                timeText: timeText,
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
        saveSourceSnapshot()
        saveTargetSnapshots()
        refreshFormat()
    }

    private func findOrMakeCity(timezoneId: String) -> CityModel {
        if let match = availableCities.first(where: { $0.timezoneId == timezoneId }) {
            return match
        }
        let (name, en) = CityService.matchCity(for: timezoneId)
        return CityModel(cityName: name, cityEn: en, timezoneId: timezoneId)
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

    func setSourceTime(hour: Int, minute: Int) {
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: sourceDate
        )
        components.hour = hour
        components.minute = minute
        sourceDate = Calendar.current.date(from: components) ?? sourceDate
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
        saveTargetSnapshots()
    }

    func setSource(_ city: CityModel) {
        let cityKey = CityIdentity.key(cityEn: city.cityEn, timezoneId: city.timezoneId)
        sourceCity = city
        targetCities.removeAll {
            CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId) == cityKey
        }
        saveSourceSnapshot()
        saveTargetSnapshots()
    }

    func removeTarget(id: UUID) {
        targetCities.removeAll { $0.id == id }
        saveTargetSnapshots()
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
        } catch {
            errorMessage = String(localized: "converter.add.city.failed")
        }
    }
}
