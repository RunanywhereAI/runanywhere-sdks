import Foundation
import GRDB

/// Configuration options for the GRDB database
public struct DatabaseConfiguration {

    // MARK: - Properties

    /// Database encryption passphrase (optional)
    /// Set this to enable SQLCipher encryption
    public let passphrase: String?

    /// Maximum number of reader connections in pool (for DatabasePool)
    /// Not used currently as we use DatabaseQueue for simplicity
    public let maximumReaderCount: Int

    /// Database timeout in seconds
    public let busyTimeout: TimeInterval

    /// Enable foreign key constraints
    public let foreignKeysEnabled: Bool

    /// Enable full-text search
    public let fullTextSearchEnabled: Bool

    /// Quality of service for database operations
    public let qualityOfService: QualityOfService

    /// Database checkpoint mode for WAL
    public let checkpointMode: CheckpointMode

    /// Maximum WAL size in bytes before automatic checkpoint
    public let maxWALSize: Int

    // MARK: - Initialization

    public init(
        passphrase: String? = nil,
        maximumReaderCount: Int = 5,
        busyTimeout: TimeInterval = 5.0,
        foreignKeysEnabled: Bool = true,
        fullTextSearchEnabled: Bool = false,
        qualityOfService: QualityOfService = .userInitiated,
        checkpointMode: CheckpointMode = .passive,
        maxWALSize: Int = 1_000_000
    ) {
        self.passphrase = passphrase
        self.maximumReaderCount = maximumReaderCount
        self.busyTimeout = busyTimeout
        self.foreignKeysEnabled = foreignKeysEnabled
        self.fullTextSearchEnabled = fullTextSearchEnabled
        self.qualityOfService = qualityOfService
        self.checkpointMode = checkpointMode
        self.maxWALSize = maxWALSize
    }

    // MARK: - Factory Methods

    /// Default configuration for production use
    public static var `default`: DatabaseConfiguration {
        DatabaseConfiguration()
    }

    /// Configuration optimized for testing
    public static var testing: DatabaseConfiguration {
        DatabaseConfiguration(
            busyTimeout: 1.0,
            qualityOfService: .userInteractive,
            checkpointMode: .truncate
        )
    }

    /// Configuration with encryption enabled
    public static func encrypted(passphrase: String) -> DatabaseConfiguration {
        DatabaseConfiguration(passphrase: passphrase)
    }
}

// MARK: - Checkpoint Mode

/// WAL checkpoint modes
public enum CheckpointMode {
    /// Checkpoint when WAL grows beyond threshold
    case passive

    /// More aggressive checkpointing
    case full

    /// Reset WAL after checkpoint
    case restart

    /// Truncate WAL file after checkpoint
    case truncate

    var sqliteMode: Int32 {
        switch self {
        case .passive:
            return 0 // SQLITE_CHECKPOINT_PASSIVE
        case .full:
            return 1 // SQLITE_CHECKPOINT_FULL
        case .restart:
            return 2 // SQLITE_CHECKPOINT_RESTART
        case .truncate:
            return 3 // SQLITE_CHECKPOINT_TRUNCATE
        }
    }
}
