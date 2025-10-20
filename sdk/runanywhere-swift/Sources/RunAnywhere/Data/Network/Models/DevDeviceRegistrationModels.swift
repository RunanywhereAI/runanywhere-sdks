import Foundation

// MARK: - Development Device Registration Models

/// Request model for development device registration
/// This is used when SDK is initialized in development mode
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
        case deviceId = "deviceId"
        case deviceModel = "deviceModel"
        case osVersion = "osVersion"
        case chipName = "chipName"
        case totalMemory = "totalMemory"
        case hasNeuralEngine = "hasNeuralEngine"
        case architecture
        case formFactor = "formFactor"
        case sdkVersion = "sdkVersion"
        case platform
        case buildToken = "buildToken"
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
