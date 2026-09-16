import AppIntents
import Foundation

struct OffTimeCityEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.intent.city.type", defaultValue: "City")
    )
    static var defaultQuery = OffTimeCityQuery()

    let id: String
    let cityName: String
    let cityEn: String
    let countryCode: String
    let timezoneId: String
    let workStartHour: Int
    let workEndHour: Int
    let isLocal: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(CityDisplay.primaryName(cityName: cityName, cityEn: cityEn))",
            subtitle: "\(timezoneId)"
        )
    }

    init(city: WidgetCitySnapshot) {
        id = city.id
        cityName = city.cityName
        cityEn = city.cityEn
        countryCode = city.countryCode
        timezoneId = city.timezoneId
        workStartHour = city.workStartHour
        workEndHour = city.workEndHour
        isLocal = city.isLocal
    }

    func toSnapshot() -> WidgetCitySnapshot {
        WidgetCitySnapshot(
            id: id,
            cityName: cityName,
            cityEn: cityEn,
            countryCode: countryCode,
            timezoneId: timezoneId,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            isLocal: isLocal
        )
    }
}

struct OffTimeCityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [OffTimeCityEntity] {
        let all = try await suggestedEntities()
        let wanted = Set(identifiers)
        return all.filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [OffTimeCityEntity] {
        let keyword = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return try await suggestedEntities() }
        return try await suggestedEntities().filter {
            $0.cityName.lowercased().contains(keyword)
                || $0.cityEn.lowercased().contains(keyword)
                || $0.timezoneId.lowercased().contains(keyword)
        }
    }

    func suggestedEntities() async throws -> [OffTimeCityEntity] {
        let snapshot = WidgetSnapshotStore.load() ?? .fallback()
        return snapshot.cities.map(OffTimeCityEntity.init(city:))
    }

    func defaultResult() async -> OffTimeCityEntity? {
        try? await suggestedEntities().first
    }
}

struct OffTimeWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "widget.intent.title",
        defaultValue: "OffTime Cities"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "widget.intent.description",
            defaultValue: "Pick the cities this widget shows; the order always matches your clock list."
        )
    )

    @Parameter(title: LocalizedStringResource("widget.intent.cities", defaultValue: "Cities to show"))
    var cities: [OffTimeCityEntity]?
}
