import Foundation

/// Data Transfer Object for configuration synchronization
public struct ConfigurationDTO: Codable {
    public let id: String
    public let data: ConfigurationData
    public let version: String
    public let lastModified: Date

    public init(
        id: String,
        data: ConfigurationData,
        version: String = SDKConstants.DatabaseDefaults.modelVersion,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.data = data
        self.version = version
        self.lastModified = lastModified
    }
}

/// Response from configuration sync
public struct ConfigurationSyncResponse: Codable {
    public let success: Bool
    public let syncedAt: Date
    public let serverVersion: String?
    public let conflicts: [ConfigurationConflict]?
}

/// Configuration conflict information
public struct ConfigurationConflict: Codable {
    public let field: String
    public let localValue: String
    public let serverValue: String
    public let resolution: ConflictResolution

    public enum ConflictResolution: String, Codable {
        case useLocal
        case useServer
        case merge
    }
}
