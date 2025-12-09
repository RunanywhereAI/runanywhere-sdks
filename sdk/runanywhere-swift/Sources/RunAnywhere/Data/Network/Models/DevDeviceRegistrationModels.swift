import Foundation

// MARK: - Development Device Registration Models

/// Request model for development device registration
/// This is used when SDK is initialized in development mode
/// Supports both traditional backend and Supabase formats
public struct DevDeviceRegistrationRequest: Codable {
    let deviceId: String
    let deviceModel: String
    let osVersion: String
    let architecture: String
    let platform: String
    let sdkVersion: String
    let buildToken: String
    let lastSeenAt: String  // ISO 8601 timestamp for UPSERT updates

    enum CodingKeys: String, CodingKey {
        // Use snake_case for Supabase compatibility
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

/// Response model for development device registration
public struct DevDeviceRegistrationResponse: Codable {
    let success: Bool
    let deviceId: String
    let registeredAt: String

    enum CodingKeys: String, CodingKey {
        case success
        case deviceId
        case registeredAt
    }
}
