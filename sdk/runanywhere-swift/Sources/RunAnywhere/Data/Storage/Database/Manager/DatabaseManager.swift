import Foundation
import GRDB

/// Main database coordinator for the RunAnywhere SDK
/// Manages database lifecycle, connections, and migrations
public final class DatabaseManager {

    // MARK: - Singleton

    public static let shared = DatabaseManager()

    // MARK: - Database Disabled Flag

    /// Database is currently disabled - all operations are no-ops
    /// Set to `true` to enable database functionality when needed
    public static var isEnabled: Bool = false

    // MARK: - Properties

    private var databaseQueue: DatabaseQueue?
    private let logger = SDKLogger(category: "DatabaseManager")

    /// Database file URL
    private var databaseURL: URL {
        guard let documentsPath = try? FileOperationsUtilities.getDocumentsDirectory() else {
            fatalError("Unable to access documents directory")
        }
        return documentsPath.appendingPathComponent(LifecycleConstants.databaseFileName)
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Setup

    /// Initialize the database
    /// - Throws: DatabaseError if initialization fails
    public func setup() throws {
        guard Self.isEnabled else {
            logger.info("Database is disabled - skipping setup")
            return
        }

        logger.info("Setting up database at: \(databaseURL.path)")

        do {
            // Configure GRDB
            var config = GRDB.Configuration()

            // Enable foreign key constraints
            config.foreignKeysEnabled = true

            // Set busy timeout to 5 seconds
            config.busyMode = .timeout(5.0)

            // Enable WAL mode for better concurrency
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode = WAL")

                // Performance optimizations
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
                try db.execute(sql: "PRAGMA temp_store = MEMORY")
                try db.execute(sql: "PRAGMA mmap_size = 30000000000")

                // Set busy timeout to 5 seconds
                // Note: busyMode is set on Configuration, not Database
            }

            // Development settings
            #if DEBUG
            config.publicStatementArguments = true
            config.prepareDatabase { db in
                db.trace { event in
                    // Log SQL statements in debug builds
                    if case let .statement(statement) = event {
                        self.logger.debug("SQL: \(statement)")
                    }
                }
            }
            #endif

            // Create database queue
            databaseQueue = try DatabaseQueue(
                path: databaseURL.path,
                configuration: config
            )

            // Run migrations
            try migrate()

            logger.info("Database setup completed successfully")

        } catch {
            logger.error("Failed to setup database: \(error)")
            throw DatabaseError.initializationFailed(error)
        }
    }

    // MARK: - Migration

    private func migrate() throws {
        guard let dbQueue = databaseQueue else {
            throw DatabaseError.notInitialized
        }

        var migrator = DatabaseMigrator()

        // Register migrations
        migrator.eraseDatabaseOnSchemaChange = false

        // Register all migrations
        migrator.registerMigration("v1_initial_schema") { db in
            try Migration001_InitialSchema.migrate(db)
        }

        // Run migrations
        try migrator.migrate(dbQueue)

        logger.info("Database migrations completed")
    }

    // MARK: - Database Access

    /// Get read access to the database
    /// - Parameter block: The block to execute with read access
    /// - Returns: The result of the block
    /// - Throws: DatabaseError if database is not initialized or operation fails
    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        guard Self.isEnabled else {
            throw DatabaseError.notInitialized
        }
        guard let dbQueue = databaseQueue else {
            throw DatabaseError.notInitialized
        }

        return try dbQueue.read(block)
    }

    /// Get write access to the database
    /// - Parameter block: The block to execute with write access
    /// - Returns: The result of the block
    /// - Throws: DatabaseError if database is not initialized or operation fails
    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        guard Self.isEnabled else {
            throw DatabaseError.notInitialized
        }
        guard let dbQueue = databaseQueue else {
            throw DatabaseError.notInitialized
        }

        return try dbQueue.write(block)
    }

    /// Perform a database transaction
    /// - Parameter block: The block to execute within a transaction
    /// - Returns: The result of the block
    /// - Throws: DatabaseError if database is not initialized or transaction fails
    public func inTransaction<T>(_ block: (Database) throws -> T) throws -> T {
        guard let dbQueue = databaseQueue else {
            throw DatabaseError.notInitialized
        }

        var result: T?
        try dbQueue.inTransaction { db in
            result = try block(db)
            return .commit
        }
        guard let finalResult = result else {
            throw DatabaseError.invalidData("Transaction completed but result was nil")
        }
        return finalResult
    }

    // MARK: - Observation

    /// Create a value observation
    /// - Parameter observation: The observation to start
    /// - Returns: A cancellable token
    public func observe<T>(_ observation: ValueObservation<T>) -> DatabaseCancellable? {
        guard let dbQueue = databaseQueue else {
            logger.warning("Cannot create observation: database not initialized")
            return nil
        }

        do {
            return observation.start(
                in: dbQueue,
                onError: { error in
                    self.logger.error("Observation error: \(error)")
                },
                onChange: { _ in }
            )
        } catch {
            logger.error("Failed to start observation: \(error)")
            return nil
        }
    }

    // MARK: - Maintenance

    /// Vacuum the database to reclaim space
    public func vacuum() throws {
        try write { db in
            try db.execute(sql: "VACUUM")
        }
        logger.info("Database vacuumed successfully")
    }

    /// Analyze the database for query optimization
    public func analyze() throws {
        try write { db in
            try db.execute(sql: "ANALYZE")
        }
        logger.info("Database analyzed successfully")
    }

    /// Get database statistics
    public func statistics() throws -> DatabaseStatistics {
        try read { db in
            let pageCount = try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0
            let pageSize = try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0
            let walSize = try Int.fetchOne(db, sql: "PRAGMA wal_checkpoint(PASSIVE)") ?? 0

            return DatabaseStatistics(
                sizeInBytes: Int64(pageCount * pageSize),
                walSizeInBytes: Int64(walSize * pageSize),
                tableCount: try db.tableCount()
            )
        }
    }

    // MARK: - Backup

    /// Create a backup of the database
    /// - Parameter destinationURL: The URL to save the backup
    /// - Throws: DatabaseError if backup fails
    public func backup(to destinationURL: URL) throws {
        guard let dbQueue = databaseQueue else {
            throw DatabaseError.notInitialized
        }

        try dbQueue.backup(to: DatabaseQueue(path: destinationURL.path))

        logger.info("Database backed up to: \(destinationURL.path)")
    }

    // MARK: - Shutdown

    /// Close the database connection
    public func close() {
        databaseQueue = nil
        logger.info("Database connection closed")
    }

    /// Reset the database (delete and recreate)
    /// WARNING: This will delete all data!
    public func reset() throws {
        close()

        // Delete database file and related WAL/SHM files
        FileOperationsUtilities.removeItemIfExists(at: databaseURL)
        FileOperationsUtilities.removeItemIfExists(at: databaseURL.appendingPathExtension("wal"))
        FileOperationsUtilities.removeItemIfExists(at: databaseURL.appendingPathExtension("shm"))

        // Recreate database
        try setup()

        logger.info("Database reset completed")
    }
}

// MARK: - Supporting Types

/// Database statistics
public struct DatabaseStatistics {
    public let sizeInBytes: Int64
    public let walSizeInBytes: Int64
    public let tableCount: Int

    public var totalSizeInBytes: Int64 {
        sizeInBytes + walSizeInBytes
    }

    public var sizeInMB: Double {
        Double(totalSizeInBytes) / 1024 / 1024
    }
}

// MARK: - Extensions

extension Database {
    /// Get the number of tables in the database
    func tableCount() throws -> Int {
        try Int.fetchOne(
            self,
            sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        ) ?? 0
    }
}
