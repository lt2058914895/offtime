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
                // sqlite3_open 失败时也会分配句柄，需要关闭并置空
                if let handle = db {
                    sqlite3_close(handle)
                }
                db = nil
                throw DatabaseError.openFailed
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
            throw DatabaseError.prepareFailed
        }
        
        if sqlite3_step(statement) != SQLITE_DONE {
            throw DatabaseError.stepFailed
        }
    }
    
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
                throw DatabaseError.prepareFailed
            }
            
            sqlite3_bind_text(statement, 1, city.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, city.cityName, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, city.cityEn, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, city.timezoneId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(city.sortIndex))
            sqlite3_bind_int(statement, 6, Int32(city.isTop))
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
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
                throw DatabaseError.prepareFailed
            }
            
            sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
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
                throw DatabaseError.prepareFailed
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
                throw DatabaseError.prepareFailed
            }
            
            sqlite3_bind_int(statement, 1, Int32(sortIndex))
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
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
                throw DatabaseError.prepareFailed
            }
            
            sqlite3_bind_int(statement, 1, isTop ? 1 : 0)
            sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
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
                throw DatabaseError.prepareFailed
            }
            
            sqlite3_bind_text(statement, 1, cityName, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                return sqlite3_column_int(statement, 0) > 0
            }
            
            return false
        }
    }
    
    func saveConfig(key: String, value: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            let sql = "INSERT OR REPLACE INTO app_config (key, value) VALUES (?, ?);"
            
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            
            sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
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
                throw DatabaseError.prepareFailed
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
                throw DatabaseError.prepareFailed
            }
            
            if sqlite3_step(statement) != SQLITE_DONE {
                throw DatabaseError.stepFailed
            }
        }
    }
}

enum DatabaseError: Error {
    case openFailed
    case notInitialized
    case prepareFailed
    case stepFailed
}
