import SwiftData
import XCTest
@testable import offtime

@MainActor
final class CityServiceImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: CityModel.self, ReminderModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testMergeUsesCityIdentityInsteadOfLocalizedName() throws {
        context.insert(
            CityModel(
                cityName: "金奈",
                cityEn: "Chennai",
                timezoneId: "Asia/Kolkata"
            )
        )
        try context.save()

        let imported = CityItem(
            id: UUID(),
            cityName: "钦奈",
            cityEn: "Chennai",
            timezoneId: "Asia/Kolkata",
            sortIndex: 0
        )
        try CityService.shared.importCities(
            from: encode([imported]),
            strategy: .merge,
            context: context
        )

        let cities = try context.fetch(FetchDescriptor<CityModel>())
        XCTAssertEqual(cities.count, 1)
        XCTAssertEqual(cities.first?.cityName, "金奈")
    }

    func testMergeDeduplicatesCitiesInsideImportFile() throws {
        let imported = [
            CityItem(
                id: UUID(),
                cityName: "纽约",
                cityEn: "New York",
                timezoneId: "America/New_York",
                sortIndex: 0
            ),
            CityItem(
                id: UUID(),
                cityName: "紐約",
                cityEn: "new-york",
                timezoneId: "America/New_York",
                sortIndex: 1
            )
        ]

        try CityService.shared.importCities(
            from: encode(imported),
            strategy: .merge,
            context: context
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<CityModel>()).count, 1)
    }

    private func encode(_ cities: [CityItem]) throws -> Data {
        try JSONEncoder().encode(
            CitiesExportEnvelope(
                schemaVersion: CitiesExportEnvelope.currentSchemaVersion,
                cities: cities
            )
        )
    }
}
