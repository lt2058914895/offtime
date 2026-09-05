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
            weekdaysOnly: false,
            targetTimezoneId: "Asia/Tokyo",
            targetHour: 10,
            targetMinute: 30
        )

        let models = try context.fetch(FetchDescriptor<ReminderModel>())
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.toGroup(), group)
        XCTAssertEqual(mock.requests.map(\.identifier), ["\(group.id)-daily"])
    }

    func testWeekdayReminderPersistsOneModelAndSchedulesFiveNotifications() async throws {
        let mock = MockNotificationCenter()
        let service = CityReminderService(notificationCenter: mock, modelContainer: container)

        let group = try await service.addReminder(
            cityID: UUID(),
            cityName: "北京",
            timezoneId: "Asia/Shanghai",
            hour: 10,
            minute: 0,
            weekdaysOnly: true,
            targetTimezoneId: "Europe/London",
            targetHour: 3,
            targetMinute: 0
        )

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderModel>()).count, 1)
        XCTAssertEqual(mock.requests.count, 5)
        XCTAssertTrue(mock.requests.allSatisfy { $0.identifier.hasPrefix("\(group.id)-") })
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
            weekdaysOnly: false,
            targetTimezoneId: "Europe/London",
            targetHour: 3,
            targetMinute: 0
        )

        await service.removeReminder(id: group.id)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReminderModel>()).count, 0)
        XCTAssertEqual(mock.requests.count, 0)
        XCTAssertEqual(mock.removedPendingIdentifiers.last, ["\(group.id)-daily"])
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
            weekdaysOnly: false,
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
            weekdaysOnly: false,
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
            "weekdaysOnly": group.weekdaysOnly,
            "targetTimezoneId": group.targetTimezoneId,
            "targetHour": group.targetHour,
            "targetMinute": group.targetMinute
        ]
        return UNNotificationRequest(identifier: "\(group.id)-daily", content: content, trigger: nil)
    }
}
