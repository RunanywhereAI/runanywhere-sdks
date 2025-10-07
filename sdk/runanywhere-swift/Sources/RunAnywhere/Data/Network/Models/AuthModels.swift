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

/// Device information for registration
public struct DeviceRegistrationInfo: Codable {
    let architecture: String
    let availableMemory: Int64
    let batteryLevel: Double?
    let batteryState: String?
    let chipName: String?
    let coreCount: Int
    let deviceModel: String
    let deviceName: String?
    let efficiencyCores: Int?
    let formFactor: String
    let gpuFamily: String?
    let hasNeuralEngine: Bool
    let isLowPowerMode: Bool?
    let neuralEngineCores: Int?
    let osVersion: String
    let performanceCores: Int?
    let platform: String
    let totalMemory: Int64

    enum CodingKeys: String, CodingKey {
        case architecture
        case availableMemory = "available_memory"
        case batteryLevel = "battery_level"
        case batteryState = "battery_state"
        case chipName = "chip_name"
        case coreCount = "core_count"
        case deviceModel = "device_model"
        case deviceName = "device_name"
        case efficiencyCores = "efficiency_cores"
        case formFactor = "form_factor"
        case gpuFamily = "gpu_family"
        case hasNeuralEngine = "has_neural_engine"
        case isLowPowerMode = "is_low_power_mode"
        case neuralEngineCores = "neural_engine_cores"
        case osVersion = "os_version"
        case performanceCores = "performance_cores"
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
