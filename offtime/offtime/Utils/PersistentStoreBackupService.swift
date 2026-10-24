import Foundation
import SwiftData

enum AppStoreSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [CityModel.self, MeetingModel.self, ReminderModel.self]
    }
}

enum AppStoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppStoreSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

struct StoreBackupManifest: Codable {
    let createdAt: Date
    let schemaVersion: String
}

struct PersistentStoreBackupService {
    static let defaultBackupInterval: TimeInterval = 24 * 60 * 60

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func backupDirectory(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("\(storeURL.lastPathComponent)-backups", isDirectory: true)
    }

    var storeURL: URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("default.store")
        }

        return applicationSupport.appendingPathComponent("default.store")
    }

    func createBackup(for storeURL: URL, date: Date = Date(), keepCount: Int = 5) throws -> URL? {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return nil
        }

        let timestamp = Self.backupDateFormatter.string(from: date)
        let backupURL = backupDirectory(for: storeURL)
            .appendingPathComponent("backup-\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        do {
            for suffix in Self.storeFileSuffixes where fileManager.fileExists(
                atPath: Self.storeFileURL(storeURL, suffix: suffix).path
            ) {
                let source = Self.storeFileURL(storeURL, suffix: suffix)
                let destination = backupURL.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: destination)
            }

            let manifest = StoreBackupManifest(
                createdAt: date,
                schemaVersion: AppStoreSchemaV1.versionIdentifier.description
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: backupURL.appendingPathComponent("manifest.json"),
                options: .atomic
            )
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw error
        }

        cleanupOldBackups(keepCount: keepCount, for: storeURL)
        return backupURL
    }

    /// 在打开 SwiftData 前同步复制数据库，避免复制已打开的 SQLite 文件。
    /// 通过限制备份频率，避免每次启动都在主线程复制整个数据库。
    func createBackupIfNeeded(
        for storeURL: URL,
        date: Date = Date(),
        minimumInterval: TimeInterval = Self.defaultBackupInterval,
        keepCount: Int = 5
    ) throws -> URL? {
        guard shouldCreateBackup(for: storeURL, date: date, minimumInterval: minimumInterval) else {
            return nil
        }
        return try createBackup(for: storeURL, date: date, keepCount: keepCount)
    }

    func shouldCreateBackup(
        for storeURL: URL,
        date: Date = Date(),
        minimumInterval: TimeInterval = Self.defaultBackupInterval
    ) -> Bool {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return false
        }
        guard minimumInterval > 0 else {
            return true
        }
        guard let latestBackup = latestBackup(for: storeURL),
              let manifest = manifest(for: latestBackup) else {
            return true
        }
        return date.timeIntervalSince(manifest.createdAt) >= minimumInterval
    }

    func latestBackup(for storeURL: URL) -> URL? {
        backupURLs(for: storeURL).first
    }

    func restore(_ backupURL: URL, to storeURL: URL) throws {
        let backupStoreURL = backupURL.appendingPathComponent(storeURL.lastPathComponent)
        guard fileManager.fileExists(atPath: backupStoreURL.path) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [
                NSFilePathErrorKey: backupStoreURL.path
            ])
        }

        let quarantinedURL = backupURL.appendingPathComponent(
            "replaced-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: quarantinedURL, withIntermediateDirectories: true)

        var movedItems: [(source: URL, destination: URL)] = []
        for suffix in Self.storeFileSuffixes {
            let source = Self.storeFileURL(storeURL, suffix: suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = quarantinedURL.appendingPathComponent(source.lastPathComponent)
            try fileManager.moveItem(at: source, to: destination)
            movedItems.append((source, destination))
        }

        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            for suffix in Self.storeFileSuffixes {
                let backupFileName = Self.storeFileURL(storeURL, suffix: suffix).lastPathComponent
                let source = backupURL.appendingPathComponent(backupFileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: Self.storeFileURL(storeURL, suffix: suffix)
                )
            }
        } catch {
            try? fileManager.removeItem(at: storeURL)
            for item in movedItems {
                try? fileManager.moveItem(at: item.destination, to: item.source)
            }
            throw error
        }
    }

    func quarantineCurrentStore(at storeURL: URL, date: Date = Date()) throws -> URL? {
        guard Self.storeFileSuffixes.contains(where: { suffix in
            fileManager.fileExists(atPath: Self.storeFileURL(storeURL, suffix: suffix).path)
        }) else {
            return nil
        }

        let timestamp = Self.backupDateFormatter.string(from: date)
        let quarantinedURL = backupDirectory(for: storeURL).appendingPathComponent(
            "broken-\(timestamp)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: quarantinedURL, withIntermediateDirectories: true)

        for suffix in Self.storeFileSuffixes {
            let source = Self.storeFileURL(storeURL, suffix: suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(
                at: source,
                to: quarantinedURL.appendingPathComponent(source.lastPathComponent)
            )
        }
        return quarantinedURL
    }

    func cleanupOldBackups(keepCount: Int, for storeURL: URL) {
        guard keepCount >= 0 else { return }
        let backups = backupURLs(for: storeURL)
        for backup in backups.dropFirst(keepCount) {
            try? fileManager.removeItem(at: backup)
        }
    }

    func backupURLs(for storeURL: URL) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: backupDirectory(for: storeURL),
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        return contents
            .filter { $0.lastPathComponent.hasPrefix("backup-") }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func manifest(for backupURL: URL) -> StoreBackupManifest? {
        let manifestURL = backupURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoreBackupManifest.self, from: data)
    }

    private static let storeFileSuffixes = ["", "-wal", "-shm"]

    private static func storeFileURL(_ storeURL: URL, suffix: String) -> URL {
        guard !suffix.isEmpty else { return storeURL }
        return URL(fileURLWithPath: storeURL.path + suffix)
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
