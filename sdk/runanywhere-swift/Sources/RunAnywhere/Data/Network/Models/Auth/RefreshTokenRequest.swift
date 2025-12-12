import Foundation

/// Request model for token refresh
public struct RefreshTokenRequest: Codable, Sendable {
    public let deviceId: String
    public let refreshToken: String

    public init(deviceId: String, refreshToken: String) {
        self.deviceId = deviceId
        self.refreshToken = refreshToken
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case refreshToken = "refresh_token"
    }
}
