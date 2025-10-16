import Foundation
import GRDB

/// Configuration source
public enum ConfigurationSource: String, Codable, Sendable {
    case remote
    case consumer
    case defaults
}

/// **Layer 3: Runtime Configuration** - Dynamic settings loaded from backend or set by consumer
///
/// This configuration is loaded **at runtime** and can change dynamically. It is NOT used for SDK initialization.
/// For SDK initialization parameters, use `SDKInitParams` instead.
///
/// **Configuration Precedence:**
/// 1. Consumer overrides (set via `RunAnywhere.updateConfiguration()`)
/// 2. Remote backend configuration (fetched in production mode)
/// 3. Database cache (from previous sessions)
/// 4. SDK defaults
///
/// **When to Use:**
/// - Configuring generation defaults (temperature, max tokens)
/// - Setting routing policy (device-only, prefer-cloud, etc.)
/// - Adjusting storage limits
/// - Enabling/disabling features
///
/// **How to Access:**
/// ```swift
/// // Read current configuration
/// let settings = await RunAnywhere.getCurrentGenerationSettings()
/// let policy = await RunAnywhere.getCurrentRoutingPolicy()
///
/// // Update configuration
/// try await RunAnywhere.updateConfiguration(preset: .creative)
/// try await RunAnywhere.setRoutingPolicy(.preferDevice)
/// ```
///
/// Main configuration data structure using composed configurations.
/// Works for both network API and database storage.
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
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
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

// MARK: - Factory Methods

extension ConfigurationData {
    /// Create SDK default configuration
    public static func sdkDefaults(apiKey: String) -> ConfigurationData {
        return ConfigurationData(
            id: "default-\(UUID().uuidString)",
            apiKey: apiKey.isEmpty ? "dev-mode" : apiKey,
            source: .defaults
        )
    }
}
