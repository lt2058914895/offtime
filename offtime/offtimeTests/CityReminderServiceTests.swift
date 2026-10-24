import SwiftData
import UserNotifications
import XCTest
@testable import offtime

@MainActor
private final class MockNotificationCenter: UserNotificationCenterProtocol {
    var requestAuthorizationResult = true
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var requests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [[String]] = []
    private(set) var removedDeliveredIdentifiers: [[String]] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        requests
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedPendingIdentifiers.append(identifiers)
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        removedDeliveredIdentifiers.append(identifiers)
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatus
    }
}

@MainActor
final class CityReminderServiceTests: XCTestCase {
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

    func testAddReminderPersistsModelAndSchedulesDailyNotification() async throws {
        let mock = MockNotificationCenter()
        let service = CityReminderService(notificationCenter: mock, modelContainer: container)
        let cityID = UUID()

        let group = try await service.addReminder(
            cityID: cityID,
            cityName: "上海",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 30,
            weekdayPolicy: .everyDay,
            targetTimezoneId: "Asia/Tokyo",
            targetHour: 10,
            targetMinute: 30
        )

        let models = try context.fetch(FetchDescriptor<ReminderModel>())
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.toGroup(), group)
        XCTAssertEqual(mock.requests.map(\.identifier), ["\(group.id)-daily"])
        XCTAssertEqual(
            mock.requests.first?.content.userInfo["weekdayPolicy"] as? String,
            CityReminderWeekdayPolicy.everyDay.rawValue
        )
    }

    func testLegacyWeekdaysOnlyModelFallsBackToBothCitiesPolicy() throws {
        let reminder = ReminderModel(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            weekdayPolicy: .bothCities,
            targetTimezoneId: "America/Los_Angeles",
            targetHour: 18,
            targetMinute: 0
        )
        reminder.weekdayPolicyRaw = nil
        reminder.weekdaysOnly = true

        XCTAssertEqual(reminder.toGroup().weekdayPolicy, .bothCities)
    }

    func testWeekdayReminderPersistsOneModelAndSchedulesFiveNotifications() async throws {
        let mock = MockNotificationCenter()
        let fixedNow = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let service = CityReminderService(
            notificationCenter: mock,
            modelContainer: container,
            now: { fixedNow }
        )

        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 10,
            minute: 0,
            weekdayPolicy: .bothCities,
            targetTimezoneId: "Europe/London",
            targetHour: 3,
            targetMinute: 0
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderModel>()).count, 1)
        XCTAssertEqual(mock.requests.count, 5)
        XCTAssertTrue(mock.requests.allSatisfy { $0.identifier.hasPrefix("\(group.id)-") })
    }

    func testBothCitiesWeekdayReminderSchedulesOnlyCommonWeekdays() async throws {
        let mock = MockNotificationCenter()
        let fixedNow = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let service = CityReminderService(
            notificationCenter: mock,
            modelContainer: container,
            now: { fixedNow }
        )

        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            weekdayPolicy: .bothCities,
            targetTimezoneId: "America/Los_Angeles",
            targetHour: 18,
            targetMinute: 0
        )

        XCTAssertEqual(
            mock.requests.map(\.identifier),
            [3, 4, 5, 6].map { "\(group.id)-\($0)" }
        )
    }

    func testCurrentCityWeekdayReminderSchedulesLocalWorkdays() async throws {
        let mock = MockNotificationCenter()
        let fixedNow = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let service = CityReminderService(
            notificationCenter: mock,
            modelContainer: container,
            now: { fixedNow }
        )

        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            weekdayPolicy: .currentCity,
            targetTimezoneId: "America/Los_Angeles",
            targetHour: 18,
            targetMinute: 0
        )

        XCTAssertEqual(
            mock.requests.map(\.identifier),
            [2, 3, 4, 5, 6].map { "\(group.id)-\($0)" }
        )
    }

    func testTargetCityWeekdayReminderSchedulesDaysThatAreWorkdaysThere() async throws {
        let mock = MockNotificationCenter()
        let fixedNow = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let service = CityReminderService(
            notificationCenter: mock,
            modelContainer: container,
            now: { fixedNow }
        )

        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            weekdayPolicy: .targetCity,
            targetTimezoneId: "America/Los_Angeles",
            targetHour: 18,
            targetMinute: 0
        )

        XCTAssertEqual(
            mock.requests.map(\.identifier),
            [3, 4, 5, 6, 7].map { "\(group.id)-\($0)" }
        )
    }

    func testRemoveReminderDeletesModelAndNotifications() async throws {
        let mock = MockNotificationCenter()
        let service = CityReminderService(notificationCenter: mock, modelContainer: container)
        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 10,
            minute: 0,
            weekdayPolicy: .everyDay,
            targetTimezoneId: "Europe/London",
            targetHour: 3,
            targetMinute: 0
        )

        await service.removeReminder(id: group.id)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderModel>()).count, 0)
        XCTAssertEqual(mock.requests.count, 0)
        XCTAssertTrue(mock.removedPendingIdentifiers.last?.contains("\(group.id)-daily") == true)
        XCTAssertTrue(mock.removedPendingIdentifiers.last?.contains("\(group.id)-3") == true)
    }

    func testRemoveReminderAlsoClearsAlreadyDeliveredNotification() async throws {
        let mock = MockNotificationCenter()
        let service = CityReminderService(notificationCenter: mock, modelContainer: container)
        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 10,
            minute: 0,
            weekdayPolicy: .everyDay,
            targetTimezoneId: "Europe/London",
            targetHour: 3,
            targetMinute: 0
        )

        // 已送达的通知不再出现在 pending 列表中，删除提醒时仍应清理通知中心里的记录。
        mock.requests = []
        await service.removeReminder(id: group.id)

        XCTAssertTrue(mock.removedDeliveredIdentifiers.last?.contains("\(group.id)-daily") == true)
        XCTAssertTrue(mock.removedDeliveredIdentifiers.last?.contains("\(group.id)-3") == true)
    }

    func testSynchronizeImportsLegacyNotificationReminder() async throws {
        let cityID = UUID()
        let city = CityModel(cityName: "上海", cityEn: "Shanghai", timezoneId: "Asia/Shanghai", sortIndex: 0)
        city.id = cityID
        context.insert(city)
        try context.save()

        let legacyGroup = CityReminderGroup(
            id: UUID().uuidString,
            cityID: cityID,
            cityName: "上海",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            weekdayPolicy: .everyDay,
            targetTimezoneId: "Asia/Tokyo",
            targetHour: 10,
            targetMinute: 0
        )
        let mock = MockNotificationCenter()
        mock.requests = [legacyNotificationRequest(for: legacyGroup)]
        let service = CityReminderService(notificationCenter: mock, modelContainer: container)

        await service.synchronize()

        let models = try context.fetch(FetchDescriptor<ReminderModel>())
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.toGroup(), legacyGroup)
        XCTAssertEqual(mock.requests.count, 1)
        XCTAssertNotNil(mock.requests.first?.content.userInfo["scheduleVersion"])
    }

    func testSynchronizeReschedulesMissingNotification() async throws {
        let cityID = UUID()
        let city = CityModel(cityName: "北京", cityEn: "Beijing", timezoneId: "Asia/Shanghai", sortIndex: 0)
        city.id = cityID
        context.insert(city)

        let reminder = ReminderModel(
            cityID: cityID,
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 10,
            minute: 0,
            weekdayPolicy: .everyDay,
            targetTimezoneId: "Europe/London",
            targetHour: 3,
            targetMinute: 0
        )
        context.insert(reminder)
        try context.save()

        let mock = MockNotificationCenter()
        let service = CityReminderService(notificationCenter: mock, modelContainer: container)

        await service.synchronize()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderModel>()).count, 1)
        XCTAssertEqual(mock.requests.map(\.identifier), ["\(reminder.id.uuidString)-daily"])
    }

    func testSynchronizeReplacesStaleWeekdayNotifications() async throws {
        let cityID = UUID()
        let city = CityModel(cityName: "北京", cityEn: "Beijing", timezoneId: "Asia/Shanghai", sortIndex: 0)
        city.id = cityID
        context.insert(city)
        try context.save()

        let group = CityReminderGroup(
            id: UUID().uuidString,
            cityID: cityID,
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 9,
            minute: 0,
            weekdayPolicy: .bothCities,
            targetTimezoneId: "America/Los_Angeles",
            targetHour: 18,
            targetMinute: 0
        )
        let baseRequest = legacyNotificationRequest(for: group)
        let mock = MockNotificationCenter()
        mock.requests = [2, 3, 4, 5, 6].map { weekday in
            UNNotificationRequest(
                identifier: "\(group.id)-\(weekday)",
                content: baseRequest.content,
                trigger: nil
            )
        }
        let fixedNow = try date(
            timezoneId: "Asia/Shanghai",
            year: 2026,
            month: 8,
            day: 23,
            hour: 10,
            minute: 0
        )
        let service = CityReminderService(
            notificationCenter: mock,
            modelContainer: container,
            now: { fixedNow }
        )

        await service.synchronize()

        XCTAssertEqual(
            mock.requests.map(\.identifier),
            [3, 4, 5, 6].map { "\(group.id)-\($0)" }
        )
    }

    func testNotificationDeliveryAvailabilityReflectsAuthorizationStatus() async {
        let mock = MockNotificationCenter()
        let service = CityReminderService(notificationCenter: mock)

        mock.authorizationStatus = .authorized
        var isAvailable = await service.isNotificationDeliveryAvailable()
        XCTAssertTrue(isAvailable)

        mock.authorizationStatus = .provisional
        isAvailable = await service.isNotificationDeliveryAvailable()
        XCTAssertTrue(isAvailable)

        mock.authorizationStatus = .ephemeral
        isAvailable = await service.isNotificationDeliveryAvailable()
        XCTAssertTrue(isAvailable)

        mock.authorizationStatus = .denied
        isAvailable = await service.isNotificationDeliveryAvailable()
        XCTAssertFalse(isAvailable)

        mock.authorizationStatus = .notDetermined
        isAvailable = await service.isNotificationDeliveryAvailable()
        XCTAssertFalse(isAvailable)
    }

    private func legacyNotificationRequest(for group: CityReminderGroup) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = group.cityName
        content.userInfo = [
            "reminderID": group.id,
            "cityID": group.cityID.uuidString,
            "cityName": group.cityName,
            "timezoneId": group.timezoneId,
            "hour": group.hour,
            "minute": group.minute,
            "weekdaysOnly": group.weekdayPolicy.legacyWeekdaysOnly,
            "targetTimezoneId": group.targetTimezoneId,
            "targetHour": group.targetHour,
            "targetMinute": group.targetMinute
        ]
        return UNNotificationRequest(identifier: "\(group.id)-daily", content: content, trigger: nil)
    }

    private func date(
        timezoneId: String,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) throws -> Date {
        let timezone = try XCTUnwrap(TimeZone(identifier: timezoneId))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
