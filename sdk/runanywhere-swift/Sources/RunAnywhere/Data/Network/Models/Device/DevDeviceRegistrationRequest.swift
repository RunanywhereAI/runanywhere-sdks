import Foundation

/// Request model for development device registration
/// Used when SDK is initialized in development mode
/// Supports both traditional backend and Supabase formats
public struct DevDeviceRegistrationRequest: Codable, Sendable {
    public let deviceId: String
    public let deviceModel: String
    public let osVersion: String
    public let architecture: String
    public let platform: String
    public let sdkVersion: String
    public let buildToken: String
    public let lastSeenAt: String

    public init(
        deviceId: String,
        deviceModel: String,
        osVersion: String,
        architecture: String,
        platform: String,
        sdkVersion: String,
        buildToken: String,
        lastSeenAt: String
    ) {
        self.deviceId = deviceId
        self.deviceModel = deviceModel
        self.osVersion = osVersion
        self.architecture = architecture
        self.platform = platform
        self.sdkVersion = sdkVersion
        self.buildToken = buildToken
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case architecture
        case platform
        case sdkVersion = "sdk_version"
        case buildToken = "build_token"
        case lastSeenAt = "last_seen_at"
    }
}
