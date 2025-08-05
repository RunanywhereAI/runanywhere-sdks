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

// MARK: - Migration Support

/// Legacy configuration data structure for migration
internal struct LegacyConfigurationData: Codable {
    let id: String
    let temperature: Float
    let maxTokens: Int
    let topP: Float
    let topK: Int
    let cloudRoutingEnabled: Bool
    let privacyModeEnabled: Bool
    let routingPolicy: String
    let allowUserOverride: Bool
    let apiKey: String?
    let analyticsEnabled: Bool
    let analyticsLevel: String
    let enableLiveMetrics: Bool
    let updatedAt: Date
    let syncPending: Bool
}

/// Migration helper for converting legacy data
public struct ConfigurationMigration {
    /// Migrates from legacy configuration format to new format
    public static func migrateFromLegacy(_ legacy: LegacyConfigurationData) -> ConfigurationData {
        // Create routing configuration
        let routingPolicy = RoutingPolicy(rawValue: legacy.routingPolicy) ?? .deviceOnly
        let privacyMode: PrivacyMode = legacy.privacyModeEnabled ? .enhanced : .standard
        let routing = RoutingConfiguration(
            policy: routingPolicy,
            cloudEnabled: legacy.cloudRoutingEnabled,
            privacyMode: privacyMode
        )

        // Create analytics configuration
        let analyticsLevel = AnalyticsLevel(rawValue: legacy.analyticsLevel) ?? .basic
        let analytics = AnalyticsConfiguration(
            enabled: legacy.analyticsEnabled,
            level: analyticsLevel,
            liveMetricsEnabled: legacy.enableLiveMetrics
        )

        // Create generation configuration
        let generationDefaults = DefaultGenerationSettings(
            temperature: Double(legacy.temperature),
            maxTokens: legacy.maxTokens,
            topP: Double(legacy.topP),
            topK: legacy.topK
        )
        let generation = GenerationConfiguration(defaults: generationDefaults)

        // Use default storage configuration
        let storage = StorageConfiguration()

        return ConfigurationData(
            id: legacy.id,
            routing: routing,
            analytics: analytics,
            generation: generation,
            storage: storage,
            apiKey: legacy.apiKey,
            allowUserOverride: legacy.allowUserOverride,
            updatedAt: legacy.updatedAt,
            syncPending: legacy.syncPending
        )
    }
}
