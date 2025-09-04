import Foundation

// MARK: - Authentication Models

/// Request model for authentication
public struct AuthenticationRequest: Codable {
    let apiKey: String
    let deviceId: String?
    let sdkVersion: String
    let platform: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case deviceId = "device_id"
        case sdkVersion = "sdk_version"
        case platform
    }
}

/// Response model for authentication
public struct AuthenticationResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Health Check Models

/// Response model for health check
public struct HealthCheckResponse: Codable {
    let status: HealthStatus
    let version: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case status
        case version
        case timestamp
    }
}

/// Health status enum
public enum HealthStatus: String, Codable {
    case healthy
    case degraded
    case unhealthy
}
