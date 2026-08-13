import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseRepository {
    static let shared = DatabaseRepository()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.offtime.database", attributes: [])
    
    private init() {}
    
    func setup() throws {
        try dbQueue.sync {
            // 幂等：如果已经初始化则跳过
            if db != nil { return }
            
            let dbURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appending(path: "offtime.sqlite")
            
            if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
                let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                if let handle = db {
                    sqlite3_close(handle)
                }
                db = nil
                throw DatabaseError.openFailed(message: errorMessage)
            }
            
            // 启用 WAL 模式，提升并发读性能
            let pragmaWal = "PRAGMA journal_mode=WAL;"
            var walStatement: OpaquePointer?
            defer { sqlite3_finalize(walStatement) }
            if sqlite3_prepare_v2(db, pragmaWal, -1, &walStatement, nil) == SQLITE_OK {
                sqlite3_step(walStatement)
            }
            
            let createUserCityTable = """
            CREATE TABLE IF NOT EXISTS user_city (
                id TEXT PRIMARY KEY,
                city_name TEXT NOT NULL,
                city_en TEXT NOT NULL,
                timezone_id TEXT NOT NULL,
                sort_index INTEGER NOT NULL
            );
            """

            let createAppConfigTable = """
            CREATE TABLE IF NOT EXISTS app_config (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """

            try executeStatement(createUserCityTable)
            try executeStatement(createAppConfigTable)

            // 版本化迁移：按 user_version 阶梯执行结构变更，保证老用户平滑升级
            try migrateSchema()
        }
    }

    /// 当前数据库 schema 版本。
    /// v1: 初始结构（user_city 含 is_top 列，已废弃）。
    /// v2: 移除 is_top 列（置顶功能已下线）。
    private let currentSchemaVersion: Int = 2

    /// 读取 PRAGMA user_version（未设过时返回 0）
    private func readUserVersion() -> Int {
        guard let db = db else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK,
           sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
        }
        return 0
    }

    private func setUserVersion(_ version: Int) {
        guard let db = db else { return }
        sqlite3_exec(db, "PRAGMA user_version = \(version);", nil, nil, nil)
    }

    /// 判断某列是否存在（幂等迁移：新用户表已是最新结构时跳过 ALTER）
    private func columnExists(_ table: String, _ column: String) -> Bool {
        guard let db = db else { return false }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "PRAGMA table_info(\(table));"
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let name = sqlite3_column_text(statement, 1) {
                    if String(cString: name) == column {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// 按版本阶梯执行迁移。每次升级只做增量 ALTER，幂等（已执行的步骤靠 user_version 跳过）。
    /// 在 setup 的 dbQueue.sync 块内调用，本身不再 sync，避免串行队列嵌套死锁。
    private func migrateSchema() throws {
        let current = readUserVersion()
        guard current < currentSchemaVersion else { return }

        // v0/v1 -> v2: 移除已废弃的 is_top 列。
        // 新用户建表已无该列，columnExists 为 false 会跳过；老用户表有该列则 DROP COLUMN。
        if current < 2 {
            if columnExists("user_city", "is_top") {
                guard let db = db else { throw DatabaseError.notInitialized }
                if sqlite3_exec(db, "ALTER TABLE user_city DROP COLUMN is_top;", nil, nil, nil) != SQLITE_OK {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.migrationFailed(message: "drop is_top: \(msg)")
                }
            }
        }

        setUserVersion(currentSchemaVersion)
    }
    
    private func executeStatement(_ sql: String) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(message: msg)
        }
        
        if sqlite3_step(statement) != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.stepFailed(message: msg)
        }
    }
    
    // MARK: - City CRUD

    func addCity(_ city: CityRecord) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = """
            INSERT INTO user_city (id, city_name, city_en, timezone_id, sort_index)
            VALUES (?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            sqlite3_bind_text(statement, 1, city.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, city.cityName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, city.cityEn, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, city.timezoneId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(city.sortIndex))

            if sqlite3_step(statement) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.stepFailed(message: msg)
            }
        }
    }
    
    func deleteCity(id: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "DELETE FROM user_city WHERE id = ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }

            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.stepFailed(message: msg)
            }
        }
    }

    /// 批量删除城市。必须在「单次」dbQueue.sync 内完成整段事务，
    /// 不能复用 performTransaction + deleteCity 的组合——那会在串行队列上 sync 套 sync，死锁。
    func deleteCities(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "DELETE FROM user_city WHERE id = ?;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }

            try executeStatement("BEGIN TRANSACTION;")
            do {
                for id in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(statement) != SQLITE_DONE {
                        let msg = String(cString: sqlite3_errmsg(db))
                        throw DatabaseError.stepFailed(message: msg)
                    }
                }
                try executeStatement("COMMIT;")
            } catch {
                try? executeStatement("ROLLBACK;")
                throw error
            }
        }
    }
    
    func getAllCities() throws -> [CityRecord] {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "SELECT id, city_name, city_en, timezone_id, sort_index FROM user_city ORDER BY sort_index ASC;"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            var cities: [CityRecord] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let cityName = String(cString: sqlite3_column_text(statement, 1))
                let cityEn = String(cString: sqlite3_column_text(statement, 2))
                let timezoneId = String(cString: sqlite3_column_text(statement, 3))
                let sortIndex = Int(sqlite3_column_int(statement, 4))

                cities.append(CityRecord(
                    id: id,
                    cityName: cityName,
                    cityEn: cityEn,
                    timezoneId: timezoneId,
                    sortIndex: sortIndex
                ))
            }
            
            return cities
        }
    }
    
    /// 获取当前最大的 sort_index。空表返回 -1，使下一个城市的 sort_index 为 0。
    /// 用 SQL MAX 单语句替代曾经的 getAllCities().max() 全表读取。
    func getMaxSortIndex() throws -> Int {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "SELECT MAX(sort_index) FROM user_city;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }

            if sqlite3_step(statement) == SQLITE_ROW {
                // 空表时 MAX 返回 NULL，返回 -1 以保证首城 sort_index = 0（与旧 max()??-1 行为一致）
                if sqlite3_column_type(statement, 0) == SQLITE_NULL {
                    return -1
                }
                return Int(sqlite3_column_int(statement, 0))
            }
            return -1
        }
    }

    func updateCitySortIndex(id: String, sortIndex: Int) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "UPDATE user_city SET sort_index = ? WHERE id = ?;"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            sqlite3_bind_int(statement, 1, Int32(sortIndex))
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.stepFailed(message: msg)
            }
        }
    }

    /// 原子性地批量更新排序：在「单次」dbQueue.sync 内完成整段事务，
    /// 任一更新失败则整体回滚，避免半更新导致排序错乱。
    /// 不能在事务块里再调用 updateCitySortIndex 等各自 dbQueue.sync 的方法——串行队列 sync 套 sync 死锁。
    func updateSortIndices(_ idIndexPairs: [(id: String, sortIndex: Int)]) throws {
        guard !idIndexPairs.isEmpty else { return }
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "UPDATE user_city SET sort_index = ? WHERE id = ?;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }

            try executeStatement("BEGIN TRANSACTION;")
            do {
                for pair in idIndexPairs {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_int(statement, 1, Int32(pair.sortIndex))
                    sqlite3_bind_text(statement, 2, pair.id, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(statement) != SQLITE_DONE {
                        let msg = String(cString: sqlite3_errmsg(db))
                        throw DatabaseError.stepFailed(message: msg)
                    }
                }
                try executeStatement("COMMIT;")
            } catch {
                try? executeStatement("ROLLBACK;")
                throw error
            }
        }
    }
    
    /// 判重改为 (cityName, timezoneId) 联合唯一：
    /// 同时区不同写法（Tokyo / 東京）允许并存，不同时区同名城市不再误判，完全重复才阻止。
    func hasCity(cityName: String, timezoneId: String) throws -> Bool {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "SELECT COUNT(*) FROM user_city WHERE city_name = ? AND timezone_id = ?;"

            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }

            sqlite3_bind_text(statement, 1, cityName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, timezoneId, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                return sqlite3_column_int(statement, 0) > 0
            }

            return false
        }
    }
    
    // MARK: - Config CRUD
    
    func saveConfig(key: String, value: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "INSERT OR REPLACE INTO app_config (key, value) VALUES (?, ?);"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.stepFailed(message: msg)
            }
        }
    }
    
    func getConfig(key: String) throws -> String? {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "SELECT value FROM app_config WHERE key = ?;"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    return String(cString: text)
                }
            }
            
            return nil
        }
    }
    
    func deleteAllCities() throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "DELETE FROM user_city;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }

            if sqlite3_step(statement) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.stepFailed(message: msg)
            }
        }
    }

    /// 原子性地用给定列表替换全部城市（先清空再批量插入）。
    /// 必须在「单次」dbQueue.sync 内完成整段事务，不能在事务块里再调用 deleteAllCities/addCity
    /// 等各自 dbQueue.sync 的方法——那会在串行队列上 sync 套 sync，死锁。
    func replaceAllCities(_ records: [CityRecord]) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }

            try executeStatement("BEGIN TRANSACTION;")
            do {
                // 1. 清空
                let deleteSQL = "DELETE FROM user_city;"
                var deleteStmt: OpaquePointer?
                defer { sqlite3_finalize(deleteStmt) }
                if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) != SQLITE_OK {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.prepareFailed(message: msg)
                }
                if sqlite3_step(deleteStmt) != SQLITE_DONE {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.stepFailed(message: msg)
                }

                // 2. 批量插入（复用 prepared statement）
                let insertSQL = """
                INSERT INTO user_city (id, city_name, city_en, timezone_id, sort_index)
                VALUES (?, ?, ?, ?, ?);
                """
                var insertStmt: OpaquePointer?
                defer { sqlite3_finalize(insertStmt) }
                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
                    let msg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.prepareFailed(message: msg)
                }
                for record in records {
                    sqlite3_reset(insertStmt)
                    sqlite3_clear_bindings(insertStmt)
                    sqlite3_bind_text(insertStmt, 1, record.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 2, record.cityName, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 3, record.cityEn, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 4, record.timezoneId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(insertStmt, 5, Int32(record.sortIndex))
                    if sqlite3_step(insertStmt) != SQLITE_DONE {
                        let msg = String(cString: sqlite3_errmsg(db))
                        throw DatabaseError.stepFailed(message: msg)
                    }
                }

                try executeStatement("COMMIT;")
            } catch {
                try? executeStatement("ROLLBACK;")
                throw error
            }
        }
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(message: String)
    case notInitialized
    case prepareFailed(message: String)
    case stepFailed(message: String)
    case migrationFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            return String(localized: "db.open.failed") + ": \(msg)"
        case .notInitialized:
            return String(localized: "db.not.initialized")
        case .prepareFailed(let msg):
            return String(localized: "db.prepare.failed") + ": \(msg)"
        case .stepFailed(let msg):
            return String(localized: "db.step.failed") + ": \(msg)"
        case .migrationFailed(let msg):
            return String(localized: "db.migration.failed") + ": \(msg)"
        }
    }
}