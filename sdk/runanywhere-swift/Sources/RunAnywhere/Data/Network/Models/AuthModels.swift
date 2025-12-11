import Foundation

// MARK: - Authentication Models

/// Request model for authentication
public struct AuthenticationRequest: Codable {
    let apiKey: String
    let deviceId: String
    let platform: String
    let sdkVersion: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case deviceId = "device_id"
        case platform
        case sdkVersion = "sdk_version"
    }
}

/// Response model for authentication
public struct AuthenticationResponse: Codable {
    let accessToken: String
    let deviceId: String
    let expiresIn: Int
    let organizationId: String
    let refreshToken: String
    let tokenType: String
    let userId: String?  // Made optional since API key should be org level or user level, will see if update is neeeded.

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

// MARK: - Token Refresh Models

/// Request model for token refresh
public struct RefreshTokenRequest: Codable {
    let deviceId: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case refreshToken = "refresh_token"
    }
}

/// Response model for token refresh (same as AuthenticationResponse)
public typealias RefreshTokenResponse = AuthenticationResponse

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

// MARK: - Device Registration Models

/// Device information for registration - simplified to essential fields only
public struct DeviceRegistrationInfo: Codable {
    let architecture: String
    let deviceModel: String
    let deviceUUID: String  // Persistent device identifier to prevent duplicate registrations
    let formFactor: String
    let osVersion: String
    let platform: String
    let totalMemory: Int64

    enum CodingKeys: String, CodingKey {
        case architecture
        case deviceModel = "device_model"
        case deviceUUID = "device_uuid"
        case formFactor = "form_factor"
        case osVersion = "os_version"
        case platform
        case totalMemory = "total_memory"
    }
}

/// Request model for device registration
public struct DeviceRegistrationRequest: Codable {
    let deviceInfo: DeviceRegistrationInfo

    enum CodingKeys: String, CodingKey {
        case deviceInfo = "device_info"
    }
}

/// Response model for device registration
public struct DeviceRegistrationResponse: Codable {
    let deviceId: String
    let status: String
    let syncStatus: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case status
        case syncStatus = "sync_status"
    }
}
