import Foundation

/// Persisted SDK configuration data with strongly typed properties
public struct ConfigurationData: RepositoryEntity, Codable {
    public let id: String

    // Generation settings
    public let temperature: Float
    public let maxTokens: Int
    public let topP: Float
    public let topK: Int

    // SDK configuration
    public let cloudRoutingEnabled: Bool
    public let privacyModeEnabled: Bool
    public let routingPolicy: String
    public let allowUserOverride: Bool

    // API configuration
    public let apiKey: String?

    // Metadata
    public let updatedAt: Date
    public let syncPending: Bool

    public init(
        id: String = SDKConstants.ConfigurationDefaults.configurationId,
        temperature: Float = SDKConstants.ConfigurationDefaults.temperature,
        maxTokens: Int = SDKConstants.ConfigurationDefaults.maxTokens,
        topP: Float = SDKConstants.ConfigurationDefaults.topP,
        topK: Int = SDKConstants.ConfigurationDefaults.topK,
        cloudRoutingEnabled: Bool = SDKConstants.ConfigurationDefaults.cloudRoutingEnabled,
        privacyModeEnabled: Bool = SDKConstants.ConfigurationDefaults.privacyModeEnabled,
        routingPolicy: String = SDKConstants.ConfigurationDefaults.routingPolicy,
        allowUserOverride: Bool = SDKConstants.ConfigurationDefaults.allowUserOverride,
        apiKey: String? = nil,
        updatedAt: Date = Date(),
        syncPending: Bool = true
    ) {
        self.id = id
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.cloudRoutingEnabled = cloudRoutingEnabled
        self.privacyModeEnabled = privacyModeEnabled
        self.routingPolicy = routingPolicy
        self.allowUserOverride = allowUserOverride
        self.apiKey = apiKey
        self.updatedAt = updatedAt
        self.syncPending = syncPending
    }

    // Copy with modifications
    public func with(
        temperature: Float? = nil,
        maxTokens: Int? = nil,
        topP: Float? = nil,
        topK: Int? = nil,
        cloudRoutingEnabled: Bool? = nil,
        privacyModeEnabled: Bool? = nil,
        routingPolicy: String? = nil,
        allowUserOverride: Bool? = nil,
        apiKey: String? = nil,
        syncPending: Bool? = nil
    ) -> ConfigurationData {
        return ConfigurationData(
            id: self.id,
            temperature: temperature ?? self.temperature,
            maxTokens: maxTokens ?? self.maxTokens,
            topP: topP ?? self.topP,
            topK: topK ?? self.topK,
            cloudRoutingEnabled: cloudRoutingEnabled ?? self.cloudRoutingEnabled,
            privacyModeEnabled: privacyModeEnabled ?? self.privacyModeEnabled,
            routingPolicy: routingPolicy ?? self.routingPolicy,
            allowUserOverride: allowUserOverride ?? self.allowUserOverride,
            apiKey: apiKey ?? self.apiKey,
            updatedAt: Date(),
            syncPending: syncPending ?? true
        )
    }
}
