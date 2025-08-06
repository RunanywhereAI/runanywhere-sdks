import Foundation

/// Main configuration data structure using composed configurations
public struct ConfigurationData: Codable, RepositoryEntity {
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }

    /// Creates a copy with updated timestamp and sync flag
    public func markUpdated() -> ConfigurationData {
        var copy = self
        copy.updatedAt = Date()
        copy.syncPending = true
        return copy
    }
}
