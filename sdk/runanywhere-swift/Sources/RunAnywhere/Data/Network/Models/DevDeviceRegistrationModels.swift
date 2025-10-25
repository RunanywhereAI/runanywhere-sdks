import Foundation

// MARK: - Development Device Registration Models

/// Request model for development device registration
/// This is used when SDK is initialized in development mode
/// Supports both traditional backend and Supabase formats
public struct DevDeviceRegistrationRequest: Codable {
    let deviceId: String
    let deviceModel: String
    let osVersion: String
    let chipName: String?
    let totalMemory: Int64
    let hasNeuralEngine: Bool
    let architecture: String
    let formFactor: String
    let sdkVersion: String
    let platform: String
    let buildToken: String

    enum CodingKeys: String, CodingKey {
        // Use snake_case for Supabase compatibility
        case deviceId = "device_id"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case chipName = "chip_name"
        case totalMemory = "total_memory"
        case hasNeuralEngine = "has_neural_engine"
        case architecture
        case formFactor = "form_factor"
        case sdkVersion = "sdk_version"
        case platform
        case buildToken = "build_token"
    }
}

/// Response model for development device registration
public struct DevDeviceRegistrationResponse: Codable {
    let success: Bool
    let deviceId: String
    let registeredAt: String

    enum CodingKeys: String, CodingKey {
        case success
        case deviceId = "deviceId"
        case registeredAt = "registeredAt"
    }
}
