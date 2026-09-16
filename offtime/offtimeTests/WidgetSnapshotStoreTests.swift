import XCTest
@testable import offtime

/// 组件快照存储回归测试。
///
/// 背景：在 App 里加了城市，桌面上的组件却还是旧的。原因之一是快照存在 UserDefaults 里，
/// 扩展进程会缓存旧值，`reloadAllTimelines()` 又是在写入后立刻发起，扩展很容易读到写之前的值；
/// 改存 App Group 容器里的文件后，每次读取都是磁盘上的最新内容。
///
/// 另外「内容没变就别再请求刷新」的判断不能带时间戳，否则每次发布都会请求一次刷新，
/// 白耗 WidgetKit 的刷新配额（配额被耗尽时，真正加城市那次反而刷不出来）。
final class WidgetSnapshotStoreTests: XCTestCase {

    private func makeSnapshot(
        cityNames: [String],
        use24Hour: Bool = true,
        localTimezoneId: String = "Asia/Shanghai",
        updatedAt: Date = Date()
    ) -> WidgetSnapshot {
        let cities = cityNames.map { name in
            WidgetCitySnapshot(
                id: name,
                cityName: name,
                cityEn: name,
                countryCode: "",
                timezoneId: "Asia/Shanghai",
                workStartHour: 9,
                workEndHour: 18,
                isLocal: name == "上海"
            )
        }
        return WidgetSnapshot(
            cities: cities,
            localTimezoneId: localTimezoneId,
            use24Hour: use24Hour,
            updatedAt: updatedAt
        )
    }

    // MARK: - 内容比较

    func testHasSameContentIgnoresTimestamp() {
        let first = makeSnapshot(cityNames: ["上海", "东京"], updatedAt: Date(timeIntervalSince1970: 1_000))
        let second = makeSnapshot(cityNames: ["上海", "东京"], updatedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertTrue(first.hasSameContent(as: second))
    }

    func testHasSameContentDetectsAddedCity() {
        let before = makeSnapshot(cityNames: ["上海", "东京"])
        let after = makeSnapshot(cityNames: ["上海", "东京", "纽约"])

        XCTAssertFalse(before.hasSameContent(as: after))
    }

    func testHasSameContentDetectsReorderedCities() {
        let before = makeSnapshot(cityNames: ["上海", "东京"])
        let after = makeSnapshot(cityNames: ["东京", "上海"])

        XCTAssertFalse(before.hasSameContent(as: after))
    }

    func testHasSameContentDetectsSettingsChange() {
        let baseline = makeSnapshot(cityNames: ["上海", "东京"])

        XCTAssertFalse(baseline.hasSameContent(as: makeSnapshot(cityNames: ["上海", "东京"], use24Hour: false)))
        // 切换当前城市会改变 isLocal，组件上的「本地」标记要跟着变
        XCTAssertFalse(baseline.hasSameContent(as: makeSnapshot(cityNames: ["上海", "东京"], localTimezoneId: "Asia/Tokyo")))
    }

    // MARK: - 文件读写

    func testSaveThenLoadReturnsLatestSnapshot() throws {
        try XCTSkipUnless(WidgetSnapshotStore.isAppGroupAvailable, "App Group 不可用，跳过共享容器读写测试")

        let saved = makeSnapshot(cityNames: ["上海", "东京", "纽约"])
        WidgetSnapshotStore.save(saved)

        let loaded = try XCTUnwrap(WidgetSnapshotStore.load())
        XCTAssertTrue(loaded.hasSameContent(as: saved))
        XCTAssertEqual(loaded.cities.count, 3)
        XCTAssertTrue(WidgetSnapshotStore.isUpToDate(with: saved))
    }

    func testIsUpToDateDetectsChangedCityList() throws {
        try XCTSkipUnless(WidgetSnapshotStore.isAppGroupAvailable, "App Group 不可用，跳过共享容器读写测试")

        WidgetSnapshotStore.save(makeSnapshot(cityNames: ["上海", "东京"]))

        XCTAssertFalse(WidgetSnapshotStore.isUpToDate(with: makeSnapshot(cityNames: ["上海", "东京", "纽约"])))
    }
}
