import Foundation

/// Response model for authentication
public struct AuthenticationResponse: Codable, Sendable {
    public let accessToken: String
    public let deviceId: String
    public let expiresIn: Int
    public let organizationId: String
    public let refreshToken: String
    public let tokenType: String
    public let userId: String?

    public init(
        accessToken: String,
        deviceId: String,
        expiresIn: Int,
        organizationId: String,
        refreshToken: String,
        tokenType: String,
        userId: String?
    ) {
        self.accessToken = accessToken
        self.deviceId = deviceId
        self.expiresIn = expiresIn
        self.organizationId = organizationId
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.userId = userId
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case deviceId = "device_id"
        case expiresIn = "expires_in"
        case organizationId = "organization_id"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case userId = "user_id"
    }
}

/// Response model for token refresh (same as AuthenticationResponse)
public typealias RefreshTokenResponse = AuthenticationResponse
