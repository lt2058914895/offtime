import XCTest
@testable import offtime

/// 城市目录完整性校验：唯一性、国家码、时区合法性。
/// 唯一性判定使用 CityIdentity 身份键（规范化英文名 + IANA 时区），而非中文名。
final class CityCatalogTests: XCTestCase {
    private var cities: [CitySuggestion] = []

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "cities", withExtension: "json"))
        let data = try Data(contentsOf: url)
        cities = try JSONDecoder().decode([CitySuggestion].self, from: data)
    }

    func testCatalogNotEmpty() {
        XCTAssertFalse(cities.isEmpty)
    }

    func testUniqueIDs() {
        let ids = cities.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "城市 id 必须唯一")
    }

    func testUniqueIdentityKey() {
        let keys = cities.map { CityIdentity.key(cityEn: $0.cityEn, timezoneId: $0.timezoneId) }
        let duplicates = keys.duplicates()
        XCTAssertTrue(duplicates.isEmpty, "身份键重复: \(duplicates)")
    }

    func testUniqueNormalizedNamePerCountry() {
        let keys = cities.map { "\(CityIdentity.normalizedEnglishName($0.cityEn))|\($0.country)" }
        let duplicates = keys.duplicates()
        XCTAssertTrue(duplicates.isEmpty, "同国家英文名重复: \(duplicates)")
    }

    func testValidCountryCodes() {
        let valid = Set(Locale.isoRegionCodes)
        let bad = cities.filter { !valid.contains($0.country) }.map(\.cityName)
        XCTAssertTrue(bad.isEmpty, "非法国家码: \(bad)")
    }

    func testValidTimezones() {
        let valid = Set(TimeZone.knownTimeZoneIdentifiers)
        let bad = cities.filter { !valid.contains($0.timezoneId) }.map(\.cityName)
        XCTAssertTrue(bad.isEmpty, "非法时区: \(bad)")
    }

    func testNonEmptyNames() {
        let bad = cities.filter { $0.cityName.isEmpty || $0.cityEn.isEmpty }.map(\.id)
        XCTAssertTrue(bad.isEmpty, "存在空名称: \(bad)")
    }
}

private extension Array where Element: Hashable {
    func duplicates() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for item in self {
            if seen.contains(item) {
                result.append(item)
            } else {
                seen.insert(item)
            }
        }
        return result
    }
}
