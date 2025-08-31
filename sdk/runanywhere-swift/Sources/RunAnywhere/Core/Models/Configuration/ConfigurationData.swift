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

    /// Analytics configuration
    public var analytics: AnalyticsConfiguration

    /// Generation configuration
    public var generation: GenerationConfiguration

    /// Storage configuration
    public var storage: StorageConfiguration

    /// API configuration
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
        analytics: AnalyticsConfiguration = AnalyticsConfiguration(),
        generation: GenerationConfiguration = GenerationConfiguration(),
        storage: StorageConfiguration = StorageConfiguration(),
        apiKey: String? = nil,
        allowUserOverride: Bool = true,
        source: ConfigurationSource = .defaults,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncPending: Bool = false
    ) {
        self.id = id
        self.routing = routing
        self.analytics = analytics
        self.generation = generation
        self.storage = storage
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
        case analytics
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
