import Foundation
import GRDB

/// Adapter to make GRDB compatible with the DatabaseCore protocol
public actor GRDBDatabaseAdapter: DatabaseCore {

    private let databaseManager: DatabaseManager
    private let logger = SDKLogger(category: "GRDBDatabaseAdapter")

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    // MARK: - DatabaseCore Implementation

    public func execute(_ sql: String, parameters: [Any]) async throws {
        try databaseManager.write { db in
            let statement = try db.makeStatement(sql: sql)
            let arguments = StatementArguments(parameters)
            try statement.execute(arguments: arguments)
        }
    }

    public func query(_ sql: String, parameters: [Any]) async throws -> [[String: Any]] {
        try databaseManager.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(parameters)
            )

            return rows.map { row in
                var dict: [String: Any] = [:]
                for column in row.columnNames {
                    // Convert DatabaseValue to Any
                    dict[column] = row[column]
                }
                return dict
            }
        }
    }

    public func transaction<T>(_ block: @escaping (DatabaseCore) async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try databaseManager.inTransaction { db in
                    // Create a temporary adapter for the transaction
                    let transactionAdapter = TransactionDatabaseAdapter(database: db)

                    // Run the async block synchronously within the transaction
                    let semaphore = DispatchSemaphore(value: 0)
                    var blockResult: Result<T, Error>?

                    Task {
                        do {
                            let value = try await block(transactionAdapter)
                            blockResult = .success(value)
                        } catch {
                            blockResult = .failure(error)
                        }
                        semaphore.signal()
                    }

                    semaphore.wait()

                    switch blockResult! {
                    case .success(let value):
                        return value
                    case .failure(let error):
                        throw error
                    }
                }
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Adapter for use within a transaction
private actor TransactionDatabaseAdapter: DatabaseCore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func execute(_ sql: String, parameters: [Any]) async throws {
        let statement = try database.makeStatement(sql: sql)
        let arguments = StatementArguments(parameters)
        try statement.execute(arguments: arguments)
    }

    func query(_ sql: String, parameters: [Any]) async throws -> [[String: Any]] {
        let rows = try Row.fetchAll(
            database,
            sql: sql,
            arguments: StatementArguments(parameters)
        )

        return rows.map { row in
            var dict: [String: Any] = [:]
            for column in row.columnNames {
                // Convert DatabaseValue to Any
                dict[column] = row[column]
            }
            return dict
        }
    }

    func transaction<T>(_ block: @escaping (DatabaseCore) async throws -> T) async throws -> T {
        // Nested transactions use savepoints in GRDB
        try await block(self)
    }
}
