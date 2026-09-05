import XCTest
@testable import offtime

final class PersistentStoreBackupServiceTests: XCTestCase {
    private var rootURL: URL!
    private var storeURL: URL!
    private var service: PersistentStoreBackupService!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offtime-backup-tests-\(UUID().uuidString)", isDirectory: true)
        storeURL = rootURL.appendingPathComponent("default.store")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        service = PersistentStoreBackupService()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
        storeURL = nil
        service = nil
    }

    func testCreateBackupCopiesStoreSidecarsAndManifest() throws {
        try "database".write(to: storeURL, atomically: true, encoding: .utf8)
        try "wal".write(to: walURL, atomically: true, encoding: .utf8)

        let backup = try service.createBackup(
            for: storeURL,
            date: date(year: 2026, month: 9, day: 5),
            keepCount: 3
        )

        let backupURL = try XCTUnwrap(backup)
        XCTAssertEqual(backupURL.lastPathComponent, "backup-20260905-000000-000")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("default.store").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("default.store-wal").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupURL.appendingPathComponent("manifest.json").path
        ))
    }

    func testLatestBackupReturnsNewestBackup() throws {
        try "database".write(to: storeURL, atomically: true, encoding: .utf8)

        let older = try service.createBackup(
            for: storeURL,
            date: date(year: 2026, month: 9, day: 4),
            keepCount: 3
        )
        let newer = try service.createBackup(
            for: storeURL,
            date: date(year: 2026, month: 9, day: 5),
            keepCount: 3
        )

        XCTAssertEqual(service.latestBackup(for: storeURL), newer)
        XCTAssertNotEqual(service.latestBackup(for: storeURL), older)
    }

    func testCleanupOldBackupsKeepsRequestedCount() throws {
        try "database".write(to: storeURL, atomically: true, encoding: .utf8)
        let days = [1, 2, 3]
        for day in days {
            _ = try service.createBackup(
                for: storeURL,
                date: date(year: 2026, month: 9, day: day),
                keepCount: 5
            )
        }

        service.cleanupOldBackups(keepCount: 2, for: storeURL)

        XCTAssertEqual(service.backupURLs(for: storeURL).count, 2)
        XCTAssertEqual(
            service.latestBackup(for: storeURL)?.lastPathComponent,
            "backup-20260903-000000-000"
        )
    }

    func testRestoreReplacesStoreAndQuarantinesReplacedFiles() throws {
        try "database".write(to: storeURL, atomically: true, encoding: .utf8)
        try "wal".write(to: walURL, atomically: true, encoding: .utf8)
        let backup = try XCTUnwrap(try service.createBackup(
            for: storeURL,
            date: date(year: 2026, month: 9, day: 5),
            keepCount: 3
        ))

        try "broken-database".write(to: storeURL, atomically: true, encoding: .utf8)
        try "new-wal".write(to: walURL, atomically: true, encoding: .utf8)

        try service.restore(backup, to: storeURL)

        let restored = try String(contentsOf: storeURL, encoding: .utf8)
        let restoredWAL = try String(contentsOf: walURL, encoding: .utf8)
        XCTAssertEqual(restored, "database")
        XCTAssertEqual(restoredWAL, "wal")

        let replacedDirectory = try XCTUnwrap(try FileManager.default.contentsOfDirectory(
            at: backup,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { $0.lastPathComponent.hasPrefix("replaced-") }
        .first)
        let replacedDatabase = try String(
            contentsOf: replacedDirectory.appendingPathComponent("default.store"),
            encoding: .utf8
        )
        XCTAssertEqual(replacedDatabase, "broken-database")
    }

    func testMigrationPlanRegistersCurrentSchema() {
        XCTAssertEqual(
            AppStoreMigrationPlan.schemas.map { ObjectIdentifier($0) },
            [ObjectIdentifier(AppStoreSchemaV1.self)]
        )
        XCTAssertTrue(AppStoreMigrationPlan.stages.isEmpty)
        XCTAssertEqual(AppStoreSchemaV1.models.count, 3)
    }

    private func backupURLs() throws -> [URL] {
        service.backupURLs(for: storeURL)
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: components) ?? Date()
    }

    private var walURL: URL {
        URL(fileURLWithPath: storeURL.path + "-wal")
    }
}
