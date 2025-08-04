import Foundation
import SQLite3

/// SQLite database implementation
public actor SQLiteDatabase: DatabaseCore {
    private let db: OpaquePointer?
    private let logger = SDKLogger(category: "SQLiteDatabase")

    // MARK: - Initialization

    public init() async throws {
        // Get database path
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory,
            .userDomainMask,
            true
        ).first!

        let dbPath = (documentsPath as NSString).appendingPathComponent("runanywhere.db")

        // Open database
        var database: OpaquePointer?
        if sqlite3_open(dbPath, &database) == SQLITE_OK {
            self.db = database
            logger.info("Database opened at: \(dbPath)")

            // Create tables
            try await createTables()
        } else {
            throw RepositoryError.databaseNotInitialized
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Table Creation

    private func createTables() async throws {
        // Configuration table
        try await execute("""
            CREATE TABLE IF NOT EXISTS configuration (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                sync_pending INTEGER DEFAULT 1
            )
        """, parameters: [])

        // Telemetry table
        try await execute("""
            CREATE TABLE IF NOT EXISTS telemetry (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                sync_pending INTEGER DEFAULT 1
            )
        """, parameters: [])

        // Model metadata table
        try await execute("""
            CREATE TABLE IF NOT EXISTS model_metadata (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                sync_pending INTEGER DEFAULT 1
            )
        """, parameters: [])

        // Generation history table
        try await execute("""
            CREATE TABLE IF NOT EXISTS generation_history (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                sync_pending INTEGER DEFAULT 1
            )
        """, parameters: [])

        // User preferences table
        try await execute("""
            CREATE TABLE IF NOT EXISTS user_preferences (
                id TEXT PRIMARY KEY,
                data TEXT NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                sync_pending INTEGER DEFAULT 1
            )
        """, parameters: [])

        logger.info("Database tables created")
    }

    // MARK: - DatabaseCore Implementation

    public func execute(_ sql: String, parameters: [Any]) async throws {
        guard let db = db else {
            throw RepositoryError.databaseNotInitialized
        }

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw RepositoryError.saveFailure(error)
        }

        defer { sqlite3_finalize(statement) }

        // Bind parameters
        for (index, parameter) in parameters.enumerated() {
            let position = Int32(index + 1)

            switch parameter {
            case let value as String:
                sqlite3_bind_text(statement, position, value, -1, nil)
            case let value as Int:
                sqlite3_bind_int64(statement, position, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, position, value)
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as Date:
                sqlite3_bind_double(statement, position, value.timeIntervalSince1970)
            case let value as Bool:
                sqlite3_bind_int(statement, position, value ? 1 : 0)
            case _ as NSNull:
                sqlite3_bind_null(statement, position)
            default:
                logger.warning("Unknown parameter type: \(type(of: parameter))")
            }
        }

        // Execute
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let error = String(cString: sqlite3_errmsg(db))
            throw RepositoryError.saveFailure(error)
        }
    }

    public func query(_ sql: String, parameters: [Any] = []) async throws -> [[String: Any]] {
        guard let db = db else {
            throw RepositoryError.databaseNotInitialized
        }

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw RepositoryError.fetchFailure(error)
        }

        defer { sqlite3_finalize(statement) }

        // Bind parameters
        for (index, parameter) in parameters.enumerated() {
            let position = Int32(index + 1)

            switch parameter {
            case let value as String:
                sqlite3_bind_text(statement, position, value, -1, nil)
            case let value as Int:
                sqlite3_bind_int64(statement, position, Int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, position, value)
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as Date:
                sqlite3_bind_double(statement, position, value.timeIntervalSince1970)
            case let value as Bool:
                sqlite3_bind_int(statement, position, value ? 1 : 0)
            case _ as NSNull:
                sqlite3_bind_null(statement, position)
            default:
                logger.warning("Unknown parameter type: \(type(of: parameter))")
            }
        }

        // Fetch results
        var results: [[String: Any]] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]

            let columnCount = sqlite3_column_count(statement)
            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))

                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER:
                    row[columnName] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    if let blob = sqlite3_column_blob(statement, i) {
                        let size = sqlite3_column_bytes(statement, i)
                        row[columnName] = Data(bytes: blob, count: Int(size))
                    }
                case SQLITE_NULL:
                    row[columnName] = NSNull()
                default:
                    break
                }
            }

            results.append(row)
        }

        return results
    }

    public func transaction<T>(_ block: @escaping (DatabaseCore) async throws -> T) async throws -> T {
        try await execute("BEGIN TRANSACTION", parameters: [])

        do {
            let result = try await block(self)
            try await execute("COMMIT", parameters: [])
            return result
        } catch {
            try await execute("ROLLBACK", parameters: [])
            throw error
        }
    }
}
