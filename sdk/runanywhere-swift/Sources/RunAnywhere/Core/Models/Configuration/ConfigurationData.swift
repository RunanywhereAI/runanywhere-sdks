import Foundation
import GRDB

/// Configuration source
public enum ConfigurationSource: String, Codable, Sendable {
    case remote = "remote"
    case consumer = "consumer"
    case defaults = "defaults"
}

/// Main configuration data structure using composed configurations
/// Works for both network API and database storage
public struct ConfigurationData: Codable, RepositoryEntity, FetchableRecord, PersistableRecord, Sendable {
    /// Unique identifier for this configuration
    public let id: String

    /// Routing configuration
    public var routing: RoutingConfiguration

    /// Generation configuration
    public var generation: GenerationConfiguration

    /// Storage configuration (includes memory threshold)
    public var storage: StorageConfiguration

    /// API configuration (baseURL, timeouts, etc)
    public var api: APIConfiguration

    /// Telemetry configuration (consent, analytics settings)
    public var telemetry: TelemetryConfiguration

    /// Download configuration
    public var download: ModelDownloadConfiguration

    /// Hardware preferences (optional)
    public var hardware: HardwareConfiguration?

    /// Debug mode flag
    public var debugMode: Bool

    /// API key for authentication (optional - can be provided separately)
    public var apiKey: String?

    /// Whether user can override configuration
    public var allowUserOverride: Bool

    /// Configuration source
    public var source: ConfigurationSource = .defaults

    /// Metadata
    public let createdAt: Date
    public var updatedAt: Date
    public var syncPending: Bool

    public init(
        id: String = "default",
        routing: RoutingConfiguration = RoutingConfiguration(),
        generation: GenerationConfiguration = GenerationConfiguration(),
        storage: StorageConfiguration = StorageConfiguration(),
        api: APIConfiguration = APIConfiguration(),
        telemetry: TelemetryConfiguration = TelemetryConfiguration(),
        download: ModelDownloadConfiguration = ModelDownloadConfiguration(),
        hardware: HardwareConfiguration? = nil,
        debugMode: Bool = false,
        apiKey: String? = nil,
        allowUserOverride: Bool = true,
        source: ConfigurationSource = .defaults,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = false
    ) {
        self.id = id
        self.routing = routing
        self.generation = generation
        self.storage = storage
        self.api = api
        self.telemetry = telemetry
        self.download = download
        self.hardware = hardware
        self.debugMode = debugMode
        self.apiKey = apiKey
        self.allowUserOverride = allowUserOverride
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }

}

// MARK: - GRDB Configuration

extension ConfigurationData: TableRecord {
    /// The table name for ConfigurationData in the database
    public static let databaseTableName: String = "configuration"

    /// Define how to handle conflicts during persistence
    public static let persistenceConflictPolicy: PersistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

// MARK: - Column Names for Type-Safe Queries

extension ConfigurationData {
    public enum Columns: String, ColumnExpression {
        case id
        case routing
        case generation
        case storage
        case apiKey
        case allowUserOverride
        case source
        case createdAt
        case updatedAt
        case syncPending
    }
}
