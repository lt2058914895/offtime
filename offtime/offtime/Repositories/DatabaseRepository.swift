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
                sort_index INTEGER NOT NULL,
                is_top INTEGER NOT NULL
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
        }
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
    
    // MARK: - Transaction Support
    
    func performTransaction(_ block: () throws -> Void) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            try executeStatement("BEGIN TRANSACTION;")
            do {
                try block()
                try executeStatement("COMMIT;")
            } catch {
                // 回滚事务，忽略回滚本身的错误
                try? executeStatement("ROLLBACK;")
                throw error
            }
        }
    }
    
    // MARK: - City CRUD
    
    func addCity(_ city: CityRecord) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = """
            INSERT INTO user_city (id, city_name, city_en, timezone_id, sort_index, is_top)
            VALUES (?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_int(statement, 6, Int32(city.isTop))
            
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
    
    func getAllCities() throws -> [CityRecord] {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "SELECT id, city_name, city_en, timezone_id, sort_index, is_top FROM user_city ORDER BY is_top DESC, sort_index ASC;"
            
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
                let isTop = Int(sqlite3_column_int(statement, 5))
                
                cities.append(CityRecord(
                    id: id,
                    cityName: cityName,
                    cityEn: cityEn,
                    timezoneId: timezoneId,
                    sortIndex: sortIndex,
                    isTop: isTop
                ))
            }
            
            return cities
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
    
    func updateCityTop(id: String, isTop: Bool) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "UPDATE user_city SET is_top = ? WHERE id = ?;"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            sqlite3_bind_int(statement, 1, isTop ? 1 : 0)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.stepFailed(message: msg)
            }
        }
    }
    
    func hasCity(cityName: String) throws -> Bool {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "SELECT COUNT(*) FROM user_city WHERE city_name = ?;"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let msg = String(cString: sqlite3_errmsg(db))
                throw DatabaseError.prepareFailed(message: msg)
            }
            
            sqlite3_bind_text(statement, 1, cityName, -1, SQLITE_TRANSIENT)
            
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
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(message: String)
    case notInitialized
    case prepareFailed(message: String)
    case stepFailed(message: String)
    
    var errorDescription: String? {
        switch self {
        case .openFailed(let msg):
            return "数据库打开失败: \(msg)"
        case .notInitialized:
            return "数据库未初始化"
        case .prepareFailed(let msg):
            return "SQL准备失败: \(msg)"
        case .stepFailed(let msg):
            return "SQL执行失败: \(msg)"
        }
    }
}