import Foundation

/// Response model for SDK authentication
/// Matches backend SDKAuthenticationResponse schema
public struct AuthenticationResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let tokenType: String
    public let organizationId: String
    public let userId: String?
    public let deviceId: String?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresIn: Int = 18000,
        tokenType: String = "Bearer",
        organizationId: String,
        userId: String? = nil,
        deviceId: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.tokenType = tokenType
        self.organizationId = organizationId
        self.userId = userId
        self.deviceId = deviceId
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case organizationId = "organization_id"
        case userId = "user_id"
        case deviceId = "device_id"
    }
}

/// Response model for token refresh (same as AuthenticationResponse)
public typealias RefreshTokenResponse = AuthenticationResponse
