import Foundation
import GRDB

/// Errors specific to GRDB database operations
public enum DatabaseError: LocalizedError {

    /// Database has not been initialized
    case notInitialized

    /// Database initialization failed
    case initializationFailed(Error)

    /// Migration failed
    case migrationFailed(String, Error)

    /// Query execution failed
    case queryFailed(String, Error)

    /// Record not found
    case recordNotFound(String)

    /// Invalid data format
    case invalidData(String)

    /// Constraint violation
    case constraintViolation(String)

    /// Transaction failed
    case transactionFailed(Error)

    /// Backup operation failed
    case backupFailed(Error)

    /// Database is corrupted
    case corrupted(String)

    /// Operation timeout
    case timeout(String)

    /// Concurrent access error
    case concurrentAccess(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database has not been initialized. Call DatabaseManager.setup() first."

        case .initializationFailed(let error):
            return "Failed to initialize database: \(error.localizedDescription)"

        case .migrationFailed(let migration, let error):
            return "Migration '\(migration)' failed: \(error.localizedDescription)"

        case .queryFailed(let query, let error):
            return "Query failed: \(query). Error: \(error.localizedDescription)"

        case .recordNotFound(let identifier):
            return "Record not found: \(identifier)"

        case .invalidData(let details):
            return "Invalid data: \(details)"

        case .constraintViolation(let constraint):
            return "Database constraint violation: \(constraint)"

        case .transactionFailed(let error):
            return "Transaction failed: \(error.localizedDescription)"

        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"

        case .corrupted(let details):
            return "Database is corrupted: \(details)"

        case .timeout(let operation):
            return "Operation timed out: \(operation)"

        case .concurrentAccess(let details):
            return "Concurrent access error: \(details)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            return "Ensure DatabaseManager.setup() is called during app initialization."

        case .initializationFailed:
            return "Check database permissions and available disk space."

        case .migrationFailed:
            return "Database schema may be incompatible. Consider resetting the database."

        case .queryFailed:
            return "Check the query syntax and ensure all referenced tables/columns exist."

        case .recordNotFound:
            return "Verify the record ID is correct and the record exists."

        case .invalidData:
            return "Ensure data conforms to the expected format and constraints."

        case .constraintViolation:
            return "Check foreign key relationships and unique constraints."

        case .transactionFailed:
            return "Retry the operation or check for concurrent modifications."

        case .backupFailed:
            return "Ensure sufficient disk space and write permissions."

        case .corrupted:
            return "Database may need to be restored from backup or reset."

        case .timeout:
            return "Retry the operation or increase the timeout duration."

        case .concurrentAccess:
            return "Ensure proper synchronization of database operations."
        }
    }

    // MARK: - Helpers

    /// Convert GRDB DatabaseError to our DatabaseError
    public static func from(_ error: Error) -> DatabaseError {
        if let dbError = error as? GRDB.DatabaseError {
            switch dbError.extendedResultCode {
            case .SQLITE_CONSTRAINT:
                return .constraintViolation(dbError.message ?? "Unknown constraint")
            case .SQLITE_CORRUPT:
                return .corrupted(dbError.message ?? "Database corruption detected")
            case .SQLITE_BUSY, .SQLITE_LOCKED:
                return .timeout("Database is locked")
            default:
                return .queryFailed("Unknown", dbError)
            }
        }

        return .queryFailed("Unknown", error)
    }
}
