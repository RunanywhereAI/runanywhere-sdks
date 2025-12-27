import Foundation

/// Request model for authentication
public struct AuthenticationRequest: Codable, Sendable {
    public let apiKey: String
    public let deviceId: String
    public let platform: String
    public let sdkVersion: String

    public init(apiKey: String, deviceId: String, platform: String, sdkVersion: String) {
        self.apiKey = apiKey
        self.deviceId = deviceId
        self.platform = platform
        self.sdkVersion = sdkVersion
    }

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case deviceId = "device_id"
        case platform
        case sdkVersion = "sdk_version"
    }
}
