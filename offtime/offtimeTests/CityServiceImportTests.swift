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

    func testReplaceAssignsUniqueIDsAndContiguousSortIndexes() throws {
        let sharedID = UUID()
        let imported = [
            CityItem(
                id: sharedID,
                cityName: "纽约",
                cityEn: "New York",
                timezoneId: "America/New_York",
                sortIndex: 9
            ),
            CityItem(
                id: sharedID,
                cityName: "伦敦",
                cityEn: "London",
                timezoneId: "Europe/London",
                sortIndex: 4
            ),
            CityItem(
                id: sharedID,
                cityName: "东京",
                cityEn: "Tokyo",
                timezoneId: "Asia/Tokyo",
                sortIndex: 7
            )
        ]

        try CityService.shared.importCities(
            from: encode(imported),
            strategy: .replace,
            context: context
        )

        let cities = try context.fetch(
            FetchDescriptor<CityModel>(sortBy: [SortDescriptor(\.sortIndex)])
        )
        XCTAssertEqual(cities.count, 3)
        XCTAssertEqual(Set(cities.map(\.id)).count, 3)
        XCTAssertEqual(cities.map(\.sortIndex), [0, 1, 2])
    }

    func testReplaceDeduplicatesCityIdentityInsideImportFile() throws {
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
            strategy: .replace,
            context: context
        )

        let cities = try context.fetch(FetchDescriptor<CityModel>())
        XCTAssertEqual(cities.count, 1)
        XCTAssertEqual(cities.first?.cityName, "纽约")
    }

    func testReplaceRejectsInvalidTimezoneBeforeClearingExistingCities() throws {
        context.insert(
            CityModel(
                cityName: "上海",
                cityEn: "Shanghai",
                timezoneId: "Asia/Shanghai"
            )
        )
        try context.save()

        let invalid = CityItem(
            id: UUID(),
            cityName: "火星城",
            cityEn: "Mars City",
            timezoneId: "Mars/Olympus_Mons",
            sortIndex: 0
        )

        XCTAssertThrowsError(
            try CityService.shared.importCities(
                from: encode([invalid]),
                strategy: .replace,
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? CityError, .invalidImportData)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<CityModel>()).count, 1)
    }

    func testReplaceRejectsEmptyCityName() throws {
        let invalid = CityItem(
            id: UUID(),
            cityName: "   ",
            cityEn: "Paris",
            timezoneId: "Europe/Paris",
            sortIndex: 0
        )

        XCTAssertThrowsError(
            try CityService.shared.importCities(
                from: encode([invalid]),
                strategy: .replace,
                context: context
            )
        ) { error in
            XCTAssertEqual(error as? CityError, .invalidImportData)
        }
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
