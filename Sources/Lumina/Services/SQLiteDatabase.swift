import Foundation
import SQLite3

/// A tiny, focused SQLite wrapper. Lumina uses the C API directly so it has
/// no dependency on a database package and full control over FTS5 and BLOB
/// storage. Access is serialized by `IndexStore` (an actor).
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    var path: String {
        guard let handle else { return "" }
        return String(cString: sqlite3_db_filename(handle, "main"))
    }

    var lastInsertRowID: Int64 {
        guard let handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }

    var changes: Int {
        guard let handle else { return 0 }
        return Int(sqlite3_changes(handle))
    }

    init(url: URL) throws {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if let database { sqlite3_close_v2(database) }
            throw SQLiteError(code: result, message: message)
        }
        handle = database
        sqlite3_busy_timeout(database, 5_000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    func execute(_ sql: String) throws {
        guard let handle else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "Database is closed")
        }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            if let errorMessage { sqlite3_free(errorMessage) }
            throw SQLiteError(code: result, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let handle else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "Database is closed")
        }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(handle)))
        }
        return SQLiteStatement(statement: statement, database: handle)
    }

    func scalarInt(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql)
        guard try statement.step() else { return 0 }
        return statement.int64(0)
    }

    /// Execute several statements atomically. Used when replacing a file's
    /// chunks and FTS content so search never observes a half-written file.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}

final class SQLiteStatement {
    private let statement: OpaquePointer
    private let database: OpaquePointer

    init(statement: OpaquePointer, database: OpaquePointer) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bind(_ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(statement, index, value)
    }

    func bind(_ index: Int32, _ value: Int) {
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    func bind(_ index: Int32, _ value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    func bind(_ index: Int32, _ value: Bool) {
        sqlite3_bind_int(statement, index, value ? 1 : 0)
    }

    func bindNull(_ index: Int32) {
        sqlite3_bind_null(statement, index)
    }

    func bind(_ index: Int32, data: Data?) {
        guard let data else {
            sqlite3_bind_null(statement, index)
            return
        }
        data.withUnsafeBytes { rawBuffer in
            _ = sqlite3_bind_blob(statement, index, rawBuffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }

    @discardableResult
    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(database)))
        }
    }

    func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func string(_ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    func int64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func int(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func double(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func bool(_ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    func data(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }
}

struct SQLiteError: LocalizedError {
    let code: Int32
    let message: String

    var errorDescription: String? {
        "SQLite error \(code): \(message)"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
